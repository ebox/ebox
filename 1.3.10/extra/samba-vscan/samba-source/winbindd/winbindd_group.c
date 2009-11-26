/* 
   Unix SMB/CIFS implementation.

   Winbind daemon for ntdom nss module

   Copyright (C) Tim Potter 2000
   Copyright (C) Jeremy Allison 2001.
   Copyright (C) Gerald (Jerry) Carter 2003.
   Copyright (C) Volker Lendecke 2005
   
   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.
   
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "includes.h"
#include "winbindd.h"

#undef DBGC_CLASS
#define DBGC_CLASS DBGC_WINBIND

static void add_member(const char *domain, const char *user,
	   char **pp_members, size_t *p_num_members)
{
	fstring name;

	if (domain != NULL) {
		fill_domain_username(name, domain, user, True);
	} else {
		fstrcpy(name, user);
	}
	safe_strcat(name, ",", sizeof(name)-1);
	string_append(pp_members, name);
	*p_num_members += 1;
}

/**********************************************************************
 Add member users resulting from sid. Expand if it is a domain group.
**********************************************************************/

static void add_expanded_sid(const DOM_SID *sid,
			     char **pp_members,
			     size_t *p_num_members)
{
	DOM_SID dom_sid;
	uint32 rid;
	struct winbindd_domain *domain;
	size_t i;

	char *domain_name = NULL;
	char *name = NULL;
	enum lsa_SidType type;

	uint32 num_names;
	DOM_SID *sid_mem;
	char **names;
	uint32 *types;

	NTSTATUS result;

	TALLOC_CTX *mem_ctx = talloc_init("add_expanded_sid");

	if (mem_ctx == NULL) {
		DEBUG(1, ("talloc_init failed\n"));
		return;
	}

	sid_copy(&dom_sid, sid);
	sid_split_rid(&dom_sid, &rid);

	domain = find_lookup_domain_from_sid(sid);

	if (domain == NULL) {
		DEBUG(3, ("Could not find domain for sid %s\n",
			  sid_string_dbg(sid)));
		goto done;
	}

	result = domain->methods->sid_to_name(domain, mem_ctx, sid,
					      &domain_name, &name, &type);

	if (!NT_STATUS_IS_OK(result)) {
		DEBUG(3, ("sid_to_name failed for sid %s\n",
			  sid_string_dbg(sid)));
		goto done;
	}

	DEBUG(10, ("Found name %s, type %d\n", name, type));

	if (type == SID_NAME_USER) {
		add_member(domain_name, name, pp_members, p_num_members);
		goto done;
	}

	if (type != SID_NAME_DOM_GRP) {
		DEBUG(10, ("Alias member %s neither user nor group, ignore\n",
			   name));
		goto done;
	}

	/* Expand the domain group, this must be done via the target domain */

	domain = find_domain_from_sid(sid);

	if (domain == NULL) {
		DEBUG(3, ("Could not find domain from SID %s\n",
			  sid_string_dbg(sid)));
		goto done;
	}

	result = domain->methods->lookup_groupmem(domain, mem_ctx,
						  sid, &num_names,
						  &sid_mem, &names,
						  &types);

	if (!NT_STATUS_IS_OK(result)) {
		DEBUG(10, ("Could not lookup group members for %s: %s\n",
			   name, nt_errstr(result)));
		goto done;
	}

	for (i=0; i<num_names; i++) {
		DEBUG(10, ("Adding group member SID %s\n",
			   sid_string_dbg(&sid_mem[i])));

		if (types[i] != SID_NAME_USER) {
			DEBUG(1, ("Hmmm. Member %s of group %s is no user. "
				  "Ignoring.\n", names[i], name));
			continue;
		}

		add_member(NULL, names[i], pp_members, p_num_members);
	}

 done:
	talloc_destroy(mem_ctx);
	return;
}

static bool fill_passdb_alias_grmem(struct winbindd_domain *domain,
				    DOM_SID *group_sid, size_t *num_gr_mem,
				    char **gr_mem, size_t *gr_mem_len)
{
	DOM_SID *members;
	size_t i, num_members;

	*num_gr_mem = 0;
	*gr_mem = NULL;
	*gr_mem_len = 0;

	if (!NT_STATUS_IS_OK(pdb_enum_aliasmem(group_sid, &members,
					       &num_members)))
		return True;

	for (i=0; i<num_members; i++) {
		add_expanded_sid(&members[i], gr_mem, num_gr_mem);
	}

	TALLOC_FREE(members);

	if (*gr_mem != NULL) {
		size_t len;

		/* We have at least one member, strip off the last "," */
		len = strlen(*gr_mem);
		(*gr_mem)[len-1] = '\0';
		*gr_mem_len = len;
	}

	return True;
}

/* Fill a grent structure from various other information */

static bool fill_grent(TALLOC_CTX *mem_ctx, struct winbindd_gr *gr,
		       const char *dom_name,
		       char *gr_name, gid_t unix_gid)
{
	fstring full_group_name;
	char *mapped_name = NULL;
	struct winbindd_domain *domain = find_domain_from_name_noinit(dom_name);
	NTSTATUS nt_status = NT_STATUS_UNSUCCESSFUL;

	nt_status = normalize_name_map(mem_ctx, domain, gr_name,
				       &mapped_name);

	/* Basic whitespace replacement */
	if (NT_STATUS_IS_OK(nt_status)) {
		fill_domain_username(full_group_name, dom_name,
				     mapped_name, true);
	}
	/* Mapped to an aliase */
	else if (NT_STATUS_EQUAL(nt_status, NT_STATUS_FILE_RENAMED)) {
		fstrcpy(full_group_name, mapped_name);
	}
	/* no change */
	else {
		fill_domain_username( full_group_name, dom_name,
				      gr_name, True );
	}

	gr->gr_gid = unix_gid;

	/* Group name and password */

	safe_strcpy(gr->gr_name, full_group_name, sizeof(gr->gr_name) - 1);
	safe_strcpy(gr->gr_passwd, "x", sizeof(gr->gr_passwd) - 1);

	return True;
}

/***********************************************************************
 If "enum users" is set to false, and the group being looked
 up is the Domain Users SID: S-1-5-domain-513, then for the
 list of members check if the querying user is in that group,
 and if so only return that user as the gr_mem array.
 We can change this to a different parameter than "enum users"
 if neccessaey, or parameterize the group list we do this for.
***********************************************************************/

static bool fill_grent_mem_domusers( TALLOC_CTX *mem_ctx,
				     struct winbindd_domain *domain,
				     struct winbindd_cli_state *state,
				     DOM_SID *group_sid,
				     enum lsa_SidType group_name_type,
				     size_t *num_gr_mem, char **gr_mem,
				     size_t *gr_mem_len)
{
	DOM_SID querying_user_sid;
	DOM_SID *pquerying_user_sid = NULL;
	uint32 num_groups = 0;
	DOM_SID *user_sids = NULL;
	bool u_in_group = False;
	NTSTATUS status;
	int i;
	unsigned int buf_len = 0;
	char *buf = NULL;

	DEBUG(10,("fill_grent_mem_domain_users: domain %s\n",
		  domain->name ));

	if (state) {
		uid_t ret_uid = (uid_t)-1;
		if (sys_getpeereid(state->sock, &ret_uid)==0) {
			/* We know who's asking - look up their SID if
			   it's one we've mapped before. */
			status = idmap_uid_to_sid(domain->name,
						  &querying_user_sid, ret_uid);
			if (NT_STATUS_IS_OK(status)) {
				pquerying_user_sid = &querying_user_sid;
				DEBUG(10,("fill_grent_mem_domain_users: "
					  "querying uid %u -> %s\n",
					  (unsigned int)ret_uid,
					  sid_string_dbg(pquerying_user_sid)));
			}
		}
	}

	/* Only look up if it was a winbindd user in this domain. */
	if (pquerying_user_sid &&
	    (sid_compare_domain(pquerying_user_sid, &domain->sid) == 0)) {

		DEBUG(10,("fill_grent_mem_domain_users: querying user = %s\n",
			  sid_string_dbg(pquerying_user_sid) ));

		status = domain->methods->lookup_usergroups(domain,
							    mem_ctx,
							    pquerying_user_sid,
							    &num_groups,
							    &user_sids);
		if (!NT_STATUS_IS_OK(status)) {
			DEBUG(1, ("fill_grent_mem_domain_users: "
				  "lookup_usergroups failed "
				  "for sid %s in domain %s (error: %s)\n",
				  sid_string_dbg(pquerying_user_sid),
				  domain->name,
				  nt_errstr(status)));
		        return False;
		}

		for (i = 0; i < num_groups; i++) {
			if (sid_equal(group_sid, &user_sids[i])) {
				/* User is in Domain Users, add their name
				   as the only group member. */
				u_in_group = True;
				break;
			}
		}
	}

	if (u_in_group) {
		size_t len = 0;
		char *domainname = NULL;
		char *username = NULL;
		fstring name;
		char *mapped_name = NULL;
		enum lsa_SidType type;
		struct winbindd_domain *target_domain = NULL;
		NTSTATUS name_map_status = NT_STATUS_UNSUCCESSFUL;

		DEBUG(10,("fill_grent_mem_domain_users: "
			  "sid %s in 'Domain Users' in domain %s\n",
			  sid_string_dbg(pquerying_user_sid),
			  domain->name ));

		status = domain->methods->sid_to_name(domain, mem_ctx,
						      pquerying_user_sid,
						      &domainname,
						      &username,
						      &type);
		if (!NT_STATUS_IS_OK(status)) {
			DEBUG(1, ("could not lookup username for user "
				  "sid %s in domain %s (error: %s)\n",
				  sid_string_dbg(pquerying_user_sid),
				  domain->name,
				  nt_errstr(status)));
			return False;
		}

		target_domain = find_domain_from_name_noinit(domainname);
		name_map_status = normalize_name_map(mem_ctx, target_domain,
						     username, &mapped_name);

		/* Basic whitespace replacement */
		if (NT_STATUS_IS_OK(name_map_status)) {
			fill_domain_username(name, domainname, mapped_name, true);
		}
		/* Mapped to an alias */
		else if (NT_STATUS_EQUAL(name_map_status, NT_STATUS_FILE_RENAMED)) {
			fstrcpy(name, mapped_name);
		}
		/* no mapping done...use original name */
		else {
			fill_domain_username(name, domainname, username, true);
		}

		len = strlen(name);
		buf_len = len + 1;
		if (!(buf = (char *)SMB_MALLOC(buf_len))) {
			DEBUG(1, ("out of memory\n"));
			return False;
		}
		memcpy(buf, name, buf_len);

		DEBUG(10,("fill_grent_mem_domain_users: user %s in "
			  "'Domain Users' in domain %s\n",
			  name, domain->name ));

		/* user is the only member */
		*num_gr_mem = 1;
	}

	*gr_mem = buf;
	*gr_mem_len = buf_len;

	DEBUG(10, ("fill_grent_mem_domain_users: "
		   "num_mem = %u, len = %u, mem = %s\n",
		   (unsigned int)*num_gr_mem,
		   (unsigned int)buf_len, *num_gr_mem ? buf : "NULL"));

	return True;
}

/***********************************************************************
 Add names to a list.  Assumes  a canonical version of the string
 in DOMAIN\user
***********************************************************************/

static int namecmp( const void *a, const void *b )
{
	return StrCaseCmp( * (char * const *) a, * (char * const *) b);
}

static void sort_unique_list(char ***list, uint32 *n_list)
{
	uint32_t i;

	/* search for duplicates for sorting and looking for matching
	   neighbors */

	qsort(*list, *n_list, sizeof(char*), QSORT_CAST namecmp);

	for (i=1; i < *n_list; i++) {
		if (strcmp((*list)[i-1], (*list)[i]) == 0) {
			memmove(&((*list)[i-1]), &((*list)[i]),
				 sizeof(char*)*((*n_list)-i));
			(*n_list)--;
		}
	}
}

static NTSTATUS add_names_to_list( TALLOC_CTX *ctx,
				   char ***list, uint32 *n_list,
				   char **names, uint32 n_names )
{
	char **new_list = NULL;
	uint32 n_new_list = 0;
	int i, j;

	if ( !names || (n_names == 0) )
		return NT_STATUS_OK;

	/* Alloc the maximum size we'll need */

        if ( *list == NULL ) {
		if ((new_list = TALLOC_ARRAY(ctx, char *, n_names)) == NULL) {
			return NT_STATUS_NO_MEMORY;
		}
		n_new_list = n_names;
	} else {
		new_list = TALLOC_REALLOC_ARRAY( ctx, *list, char *,
						 (*n_list) + n_names );
		if ( !new_list )
			return NT_STATUS_NO_MEMORY;
		n_new_list = (*n_list) + n_names;
	}

	/* Add all names */

	for ( i=*n_list, j=0; i<n_new_list; i++, j++ ) {
		new_list[i] = talloc_strdup( new_list, names[j] );
	}

	*list = new_list;
	*n_list = n_new_list;

	return NT_STATUS_OK;
}

/***********************************************************************
***********************************************************************/

static NTSTATUS expand_groups( TALLOC_CTX *ctx,
			       struct winbindd_domain *d,
			       DOM_SID *glist, uint32 n_glist,
			       DOM_SID **new_glist, uint32 *n_new_glist,
			       char ***members, uint32 *n_members )
{
	int i, j;
	NTSTATUS status = NT_STATUS_OK;
	uint32 num_names = 0;
	uint32 *name_types = NULL;
	char **names = NULL;
	DOM_SID *sid_mem = NULL;
	TALLOC_CTX *tmp_ctx = NULL;
	DOM_SID *new_groups = NULL;
	size_t new_groups_size = 0;

	*members = NULL;
	*n_members = 0;
	*new_glist = NULL;
	*n_new_glist = 0;

	for ( i=0; i<n_glist; i++ ) {
		tmp_ctx = talloc_new( ctx );

		/* Lookup the group membership */

		status = d->methods->lookup_groupmem(d, tmp_ctx,
						     &glist[i], &num_names,
						     &sid_mem, &names,
						     &name_types);
		if ( !NT_STATUS_IS_OK(status) )
			goto out;

		/* Separate users and groups into two lists */

		for ( j=0; j<num_names; j++ ) {

			/* Users */
			if ( name_types[j] == SID_NAME_USER ||
			     name_types[j] == SID_NAME_COMPUTER )
			{
				status = add_names_to_list( ctx, members,
							    n_members,
							    names+j, 1 );
				if ( !NT_STATUS_IS_OK(status) )
					goto out;

				continue;
			}

			/* Groups */
			if ( name_types[j] == SID_NAME_DOM_GRP ||
			     name_types[j] == SID_NAME_ALIAS )
			{
				status = add_sid_to_array_unique(ctx,
							         &sid_mem[j],
							         &new_groups,
							         &new_groups_size);
				if (!NT_STATUS_IS_OK(status)) {
					goto out;
				}

				continue;
			}
		}

		TALLOC_FREE( tmp_ctx );
	}

	*new_glist = new_groups;
	*n_new_glist = (uint32)new_groups_size;

 out:
	TALLOC_FREE( tmp_ctx );

	return status;
}

/***********************************************************************
 Fill in the group membership field of a NT group given by group_sid
***********************************************************************/

static bool fill_grent_mem(struct winbindd_domain *domain,
			   struct winbindd_cli_state *state,
			   DOM_SID *group_sid,
			   enum lsa_SidType group_name_type,
			   size_t *num_gr_mem, char **gr_mem,
			   size_t *gr_mem_len)
{
	uint32 num_names = 0;
	unsigned int buf_len = 0, buf_ndx = 0, i;
	char **names = NULL, *buf = NULL;
	bool result = False;
	TALLOC_CTX *mem_ctx;
	uint32 group_rid;
	DOM_SID *glist = NULL;
	DOM_SID *new_glist = NULL;
	uint32 n_glist, n_new_glist;
	int max_depth = lp_winbind_expand_groups();

	if (!(mem_ctx = talloc_init("fill_grent_mem(%s)", domain->name)))
		return False;

	DEBUG(10, ("group SID %s\n", sid_string_dbg(group_sid)));

	/* Initialize with no members */

	*num_gr_mem = 0;

	/* HACK ALERT!! This whole routine does not cope with group members
	 * from more than one domain, ie aliases. Thus we have to work it out
	 * ourselves in a special routine. */

	if (domain->internal) {
		result = fill_passdb_alias_grmem(domain, group_sid,
					       num_gr_mem,
					       gr_mem, gr_mem_len);
		goto done;
	}

	/* Verify name type */

	if ( !((group_name_type==SID_NAME_DOM_GRP) ||
	       ((group_name_type==SID_NAME_ALIAS) && domain->primary)) )
	{
		DEBUG(1, ("SID %s in domain %s isn't a domain group (%d)\n",
			  sid_string_dbg(group_sid),
			  domain->name, group_name_type));
                goto done;
	}

	/* OPTIMIZATION / HACK. See comment in
	   fill_grent_mem_domusers() */

	sid_peek_rid( group_sid, &group_rid );
	if (!lp_winbind_enum_users() && group_rid == DOMAIN_GROUP_RID_USERS) {
		result = fill_grent_mem_domusers( mem_ctx, domain, state,
						  group_sid, group_name_type,
						  num_gr_mem, gr_mem,
						  gr_mem_len );
		goto done;
	}

	/* Real work goes here.  Create a list of group names to
	   expand starting with the initial one.  Pass that to
	   expand_groups() which returns a list of more group names
	   to expand.  Do this up to the max search depth. */

	if ( (glist = TALLOC_ARRAY(mem_ctx, DOM_SID, 1 )) == NULL ) {
		result = False;
		DEBUG(0,("fill_grent_mem: talloc failure!\n"));
		goto done;
	}
	sid_copy( &glist[0], group_sid );
	n_glist = 1;

	for ( i=0; i<max_depth && glist; i++ ) {
		uint32 n_members = 0;
		char **members = NULL;
		NTSTATUS nt_status;
		int j;

		nt_status = expand_groups( mem_ctx, domain,
					   glist, n_glist,
					   &new_glist, &n_new_glist,
					   &members, &n_members);
		if ( !NT_STATUS_IS_OK(nt_status) ) {
			result = False;
			goto done;
		}

		/* Add new group members to list.  Pass through the
		   alias mapping function */

		for (j=0; j<n_members; j++) {
			fstring name_domain, name_acct;
			fstring qualified_name;
			char *mapped_name = NULL;
			NTSTATUS name_map_status = NT_STATUS_UNSUCCESSFUL;
			struct winbindd_domain *target_domain = NULL;

			if (parse_domain_user(members[j], name_domain, name_acct)) {
				target_domain = find_domain_from_name_noinit(name_domain);
				/* NOW WHAT ? */
			}
			if (!target_domain) {
				target_domain = domain;
			}

			name_map_status = normalize_name_map(members, target_domain,
							     name_acct, &mapped_name);

			/* Basic whitespace replacement */
			if (NT_STATUS_IS_OK(name_map_status)) {
				fill_domain_username(qualified_name, name_domain,
						     mapped_name, true);
				mapped_name = qualified_name;
			}
			/* no mapping at all */
			else if (!NT_STATUS_EQUAL(name_map_status, NT_STATUS_FILE_RENAMED)) {
				mapped_name = members[j];
			}

			nt_status = add_names_to_list( mem_ctx, &names,
						       &num_names,
						       &mapped_name, 1);
			if ( !NT_STATUS_IS_OK(nt_status) ) {
				result = False;
				goto done;
			}
		}

		TALLOC_FREE( members );

		/* If we have no more groups to expand, break out
		   early */

		if (new_glist == NULL)
			break;

		/* One more round */
		TALLOC_FREE(glist);
		glist = new_glist;
		n_glist = n_new_glist;
	}
	TALLOC_FREE( glist );

	sort_unique_list(&names, &num_names);

	DEBUG(10, ("looked up %d names\n", num_names));

 again:
	/* Add members to list */

	for (i = 0; i < num_names; i++) {
		int len;

		DEBUG(10, ("processing name %s\n", names[i]));

		len = strlen(names[i]);

		/* Add to list or calculate buffer length */

		if (!buf) {
			buf_len += len + 1; /* List is comma separated */
			(*num_gr_mem)++;
			DEBUG(10, ("buf_len + %d = %d\n", len + 1, buf_len));
		} else {
			DEBUG(10, ("appending %s at ndx %d\n",
				   names[i], buf_ndx));
			parse_add_domuser(&buf[buf_ndx], names[i], &len);
			buf_ndx += len;
			buf[buf_ndx] = ',';
			buf_ndx++;
		}
	}

	/* Allocate buffer */

	if (!buf && buf_len != 0) {
		if (!(buf = (char *)SMB_MALLOC(buf_len))) {
			DEBUG(1, ("out of memory\n"));
			result = False;
			goto done;
		}
		memset(buf, 0, buf_len);
		goto again;
	}

	/* Now we're done */

	if (buf && buf_ndx > 0) {
		buf[buf_ndx - 1] = '\0';
	}

	*gr_mem = buf;
	*gr_mem_len = buf_len;

	DEBUG(10, ("num_mem = %u, len = %u, mem = %s\n",
		   (unsigned int)*num_gr_mem,
		   (unsigned int)buf_len, *num_gr_mem ? buf : "NULL"));
	result = True;

done:

	talloc_destroy(mem_ctx);

	DEBUG(10, ("fill_grent_mem returning %d\n", result));

	return result;
}

static void winbindd_getgrsid(struct winbindd_cli_state *state, DOM_SID group_sid);

static void getgrnam_recv( void *private_data, bool success, const DOM_SID *sid,
			   enum lsa_SidType type )
{
	struct winbindd_cli_state *state = (struct winbindd_cli_state*)private_data;

	if (!success) {
		DEBUG(5,("getgrnam_recv: lookupname failed!\n"));
		request_error(state);
		return;
	}

 	if ( (type != SID_NAME_DOM_GRP) && (type != SID_NAME_ALIAS) ) {
		DEBUG(5,("getgrnam_recv: not a group!\n"));
		request_error(state);
		return;
	}

	winbindd_getgrsid( state, *sid );
}


/* Return a group structure from a group name */

void winbindd_getgrnam(struct winbindd_cli_state *state)
{
	struct winbindd_domain *domain;
	fstring name_domain, name_group;
	char *tmp;
	NTSTATUS nt_status = NT_STATUS_UNSUCCESSFUL;

	/* Ensure null termination */
	state->request.data.groupname[sizeof(state->request.data.groupname)-1]='\0';

	DEBUG(3, ("[%5lu]: getgrnam %s\n", (unsigned long)state->pid,
		  state->request.data.groupname));

	nt_status = normalize_name_unmap(state->mem_ctx,
					 state->request.data.groupname,
					 &tmp);
	/* If we didn't map anything in the above call, just reset the
	   tmp pointer to the original string */
	if (!NT_STATUS_IS_OK(nt_status) &&
	    !NT_STATUS_EQUAL(nt_status, NT_STATUS_FILE_RENAMED))
	{
		tmp = state->request.data.groupname;
	}

	/* Parse domain and groupname */

	memset(name_group, 0, sizeof(name_group));

	name_domain[0] = '\0';
	name_group[0] = '\0';

	parse_domain_user(tmp, name_domain, name_group);

	/* if no domain or our local domain and no local tdb group, default to
	 * our local domain for aliases */

	if ( !*name_domain || strequal(name_domain, get_global_sam_name()) ) {
		fstrcpy(name_domain, get_global_sam_name());
	}

	/* Get info for the domain */

	if ((domain = find_domain_from_name_noinit(name_domain)) == NULL) {
		DEBUG(3, ("could not get domain sid for domain %s\n",
			  name_domain));
		request_error(state);
		return;
	}
	/* should we deal with users for our domain? */

	if ( lp_winbind_trusted_domains_only() && domain->primary) {
		DEBUG(7,("winbindd_getgrnam: My domain -- rejecting "
			 "getgrnam() for %s\\%s.\n", name_domain, name_group));
		request_error(state);
		return;
	}

	/* Get rid and name type from name */

	fstrcpy( name_group, tmp );

	winbindd_lookupname_async( state->mem_ctx, domain->name, name_group,
				   getgrnam_recv, WINBINDD_GETGRNAM, state );
}

struct getgrsid_state {
	struct winbindd_cli_state *state;
	struct winbindd_domain *domain;
	char *group_name;
	enum lsa_SidType group_type;
	uid_t gid;
	DOM_SID group_sid;
};

static void getgrsid_sid2gid_recv(void *private_data, bool success, gid_t gid)
{
	struct getgrsid_state *s =
		(struct getgrsid_state *)private_data;
	struct winbindd_domain *domain;
	size_t gr_mem_len;
	size_t num_gr_mem;
	char *gr_mem;
	fstring dom_name, group_name;

	if (!success) {
		DEBUG(5,("getgrsid_sid2gid_recv: sid2gid failed!\n"));
		request_error(s->state);
		return;
	}

	s->gid = gid;

	if ( !parse_domain_user( s->group_name, dom_name, group_name ) ) {
		DEBUG(5,("getgrsid_sid2gid_recv: parse_domain_user() failed!\n"));
		request_error(s->state);
		return;
	}


	/* Fill in group structure */

	if ( (domain = find_domain_from_name_noinit(dom_name)) == NULL ) {
		DEBUG(1,("Can't find domain from name (%s)\n", dom_name));
		request_error(s->state);
		return;
	}

	if (!fill_grent(s->state->mem_ctx, &s->state->response.data.gr,
			dom_name, group_name, gid) ||
	    !fill_grent_mem(domain, s->state, &s->group_sid, s->group_type,
			    &num_gr_mem, &gr_mem, &gr_mem_len))
	{
		request_error(s->state);
		return;
	}

	s->state->response.data.gr.num_gr_mem = (uint32)num_gr_mem;

	/* Group membership lives at start of extra data */

	s->state->response.data.gr.gr_mem_ofs = 0;

	s->state->response.length += gr_mem_len;
	s->state->response.extra_data.data = gr_mem;

	request_ok(s->state);
}

static void getgrsid_lookupsid_recv( void *private_data, bool success,
				     const char *dom_name, const char *name,
				     enum lsa_SidType name_type )
{
	struct getgrsid_state *s = (struct getgrsid_state *)private_data;
	char *mapped_name = NULL;
	fstring raw_name;
	NTSTATUS nt_status = NT_STATUS_UNSUCCESSFUL;

	if (!success) {
		DEBUG(5,("getgrsid_lookupsid_recv: lookupsid failed!\n"));
		request_error(s->state);
		return;
	}

	/* either it's a domain group, a domain local group, or a
	   local group in an internal domain */

 	if ( !( (name_type==SID_NAME_DOM_GRP) ||
	        ((name_type==SID_NAME_ALIAS) &&
		 (s->domain->primary || s->domain->internal)) ) )
	{
		DEBUG(1, ("name '%s\\%s' is not a local or domain group: %d\n",
			  dom_name, name, name_type));
		request_error(s->state);
		return;
	}

	/* normalize the name and ensure that we have the DOM\name
	  coming out of here */

	fstrcpy(raw_name, name);

	nt_status = normalize_name_unmap(s->state->mem_ctx, raw_name,
					 &mapped_name);

	/* basic whitespace reversal */
	if (NT_STATUS_IS_OK(nt_status)) {
		s->group_name = talloc_asprintf(s->state->mem_ctx,
						"%s%c%s",
						dom_name,
						*lp_winbind_separator(),
						mapped_name);
	}
	/* mapped from alias */
	else if (NT_STATUS_EQUAL(nt_status, NT_STATUS_FILE_RENAMED)) {
		s->group_name = mapped_name;
	}
	/* no mapping at all.  use original string */
	else {
		s->group_name = talloc_asprintf(s->state->mem_ctx,
						"%s%c%s",
						dom_name,
						*lp_winbind_separator(),
						raw_name);
	}

	if (s->group_name == NULL) {
		DEBUG(1, ("getgrsid_lookupsid_recv: group_name is NULL!\n"));
		request_error(s->state);
		return;
	}

	s->group_type = name_type;

	winbindd_sid2gid_async(s->state->mem_ctx, &s->group_sid,
			       getgrsid_sid2gid_recv, s);
}

static void winbindd_getgrsid( struct winbindd_cli_state *state, const DOM_SID group_sid )
{
	struct getgrsid_state *s;

	if ( (s = TALLOC_ZERO_P(state->mem_ctx, struct getgrsid_state)) == NULL ) {
		DEBUG(0, ("talloc failed\n"));
		request_error(state);
		return;
	}

	s->state = state;

	if ( (s->domain = find_domain_from_sid_noinit(&group_sid)) == NULL ) {
		DEBUG(3, ("Could not find domain for sid %s\n",
			  sid_string_dbg(&group_sid)));
		request_error(state);
		return;
	}

	sid_copy(&s->group_sid, &group_sid);

	winbindd_lookupsid_async( s->state->mem_ctx,  &group_sid,
				  getgrsid_lookupsid_recv, s );
}


static void getgrgid_recv(void *private_data, bool success, const char *sid)
{
	struct winbindd_cli_state *state = talloc_get_type_abort(private_data, struct winbindd_cli_state);
	enum lsa_SidType name_type;
	DOM_SID group_sid;

	if (success) {
		DEBUG(10,("getgrgid_recv: gid %lu has sid %s\n",
			  (unsigned long)(state->request.data.gid), sid));

		if (!string_to_sid(&group_sid, sid)) {
			DEBUG(1,("getgrgid_recv: Could not convert sid %s "
				"from string\n", sid));
			request_error(state);
			return;
		}

		winbindd_getgrsid(state, group_sid);
		return;
	}

	/* Ok, this might be "ours", i.e. an alias */
	if (pdb_gid_to_sid(state->request.data.gid, &group_sid) &&
	    lookup_sid(state->mem_ctx, &group_sid, NULL, NULL, &name_type) &&
	    (name_type == SID_NAME_ALIAS)) {
		/* Hey, got an alias */
		DEBUG(10,("getgrgid_recv: we have an alias with gid %lu and sid %s\n",
			  (unsigned long)(state->request.data.gid), sid));
		winbindd_getgrsid(state, group_sid);
		return;
	}

	DEBUG(1, ("could not convert gid %lu to sid\n",
		  (unsigned long)state->request.data.gid));
	request_error(state);
}

/* Return a group structure from a gid number */
void winbindd_getgrgid(struct winbindd_cli_state *state)
{
	gid_t gid = state->request.data.gid;

	DEBUG(3, ("[%5lu]: getgrgid %lu\n",
		  (unsigned long)state->pid,
		  (unsigned long)gid));

	/* always use the async interface */
	winbindd_gid2sid_async(state->mem_ctx, gid, getgrgid_recv, state);
}

/*
 * set/get/endgrent functions
 */

/* "Rewind" file pointer for group database enumeration */

static bool winbindd_setgrent_internal(struct winbindd_cli_state *state)
{
	struct winbindd_domain *domain;

	DEBUG(3, ("[%5lu]: setgrent\n", (unsigned long)state->pid));

	/* Check user has enabled this */

	if (!lp_winbind_enum_groups()) {
		return False;
	}

	/* Free old static data if it exists */

	if (state->getgrent_state != NULL) {
		free_getent_state(state->getgrent_state);
		state->getgrent_state = NULL;
	}

	/* Create sam pipes for each domain we know about */

	for (domain = domain_list(); domain != NULL; domain = domain->next) {
		struct getent_state *domain_state;

		/* Create a state record for this domain */

		/* don't add our domaina if we are a PDC or if we
		   are a member of a Samba domain */

		if ( lp_winbind_trusted_domains_only() && domain->primary )
		{
			continue;
		}

		domain_state = SMB_MALLOC_P(struct getent_state);
		if (!domain_state) {
			DEBUG(1, ("winbindd_setgrent: "
				  "malloc failed for domain_state!\n"));
			return False;
		}

		ZERO_STRUCTP(domain_state);

		fstrcpy(domain_state->domain_name, domain->name);

		/* Add to list of open domains */

		DLIST_ADD(state->getgrent_state, domain_state);
	}

	state->getgrent_initialized = True;
	return True;
}

void winbindd_setgrent(struct winbindd_cli_state *state)
{
	if (winbindd_setgrent_internal(state)) {
		request_ok(state);
	} else {
		request_error(state);
	}
}

/* Close file pointer to ntdom group database */

void winbindd_endgrent(struct winbindd_cli_state *state)
{
	DEBUG(3, ("[%5lu]: endgrent\n", (unsigned long)state->pid));

	free_getent_state(state->getgrent_state);
	state->getgrent_initialized = False;
	state->getgrent_state = NULL;
	request_ok(state);
}

/* Get the list of domain groups and domain aliases for a domain.  We fill in
   the sam_entries and num_sam_entries fields with domain group information.
   Return True if some groups were returned, False otherwise. */

bool get_sam_group_entries(struct getent_state *ent)
{
	NTSTATUS status;
	uint32 num_entries;
	struct acct_info *name_list = NULL;
	TALLOC_CTX *mem_ctx;
	bool result = False;
	struct acct_info *sam_grp_entries = NULL;
	struct winbindd_domain *domain;

	if (ent->got_sam_entries)
		return False;

	if (!(mem_ctx = talloc_init("get_sam_group_entries(%s)",
					  ent->domain_name))) {
		DEBUG(1, ("get_sam_group_entries: "
			  "could not create talloc context!\n"));
		return False;
	}

	/* Free any existing group info */

	SAFE_FREE(ent->sam_entries);
	ent->num_sam_entries = 0;
	ent->got_sam_entries = True;

	/* Enumerate domain groups */

	num_entries = 0;

	if (!(domain = find_domain_from_name(ent->domain_name))) {
		DEBUG(3, ("no such domain %s in get_sam_group_entries\n",
			  ent->domain_name));
		goto done;
	}

	/* always get the domain global groups */

	status = domain->methods->enum_dom_groups(domain, mem_ctx, &num_entries,
						  &sam_grp_entries);

	if (!NT_STATUS_IS_OK(status)) {
		DEBUG(3, ("get_sam_group_entries: "
			  "could not enumerate domain groups! Error: %s\n",
			  nt_errstr(status)));
		result = False;
		goto done;
	}

	/* Copy entries into return buffer */

	if (num_entries) {
		name_list = SMB_MALLOC_ARRAY(struct acct_info, num_entries);
		if (!name_list) {
			DEBUG(0,("get_sam_group_entries: Failed to malloc "
				 "memory for %d domain groups!\n",
				 num_entries));
			result = False;
			goto done;
		}
		memcpy(name_list, sam_grp_entries,
			num_entries * sizeof(struct acct_info));
	}

	ent->num_sam_entries = num_entries;

	/* get the domain local groups if we are a member of a native win2k
	 * domain and are not using LDAP to get the groups */

	if ( ( lp_security() != SEC_ADS && domain->native_mode
		&& domain->primary) || domain->internal )
	{
		DEBUG(4,("get_sam_group_entries: %s domain; "
			 "enumerating local groups as well\n",
			 domain->native_mode ? "Native Mode 2k":
						"BUILTIN or local"));

		status = domain->methods->enum_local_groups(domain, mem_ctx,
							    &num_entries,
							    &sam_grp_entries);

		if ( !NT_STATUS_IS_OK(status) ) {
			DEBUG(3,("get_sam_group_entries: "
				"Failed to enumerate "
				"domain local groups with error %s!\n",
				nt_errstr(status)));
			num_entries = 0;
		}
		else
			DEBUG(4,("get_sam_group_entries: "
				 "Returned %d local groups\n",
				 num_entries));

		/* Copy entries into return buffer */

		if ( num_entries ) {
			name_list = SMB_REALLOC_ARRAY(name_list,
						      struct acct_info,
						      ent->num_sam_entries+
							num_entries);
			if (!name_list) {
				DEBUG(0,("get_sam_group_entries: "
					 "Failed to realloc more memory "
					 "for %d local groups!\n",
					 num_entries));
				result = False;
				goto done;
			}

			memcpy(&name_list[ent->num_sam_entries],
				sam_grp_entries,
				num_entries * sizeof(struct acct_info));
		}

		ent->num_sam_entries += num_entries;
	}


	/* Fill in remaining fields */

	ent->sam_entries = name_list;
	ent->sam_entry_index = 0;

	result = (ent->num_sam_entries > 0);

 done:
	talloc_destroy(mem_ctx);

	return result;
}

/* Fetch next group entry from ntdom database */

#define MAX_GETGRENT_GROUPS 500

void winbindd_getgrent(struct winbindd_cli_state *state)
{
	struct getent_state *ent;
	struct winbindd_gr *group_list = NULL;
	int num_groups, group_list_ndx, gr_mem_list_len = 0;
	char *gr_mem_list = NULL;

	DEBUG(3, ("[%5lu]: getgrent\n", (unsigned long)state->pid));

	/* Check user has enabled this */

	if (!lp_winbind_enum_groups()) {
		request_error(state);
		return;
	}

	num_groups = MIN(MAX_GETGRENT_GROUPS, state->request.data.num_entries);

	if (num_groups == 0) {
		request_error(state);
		return;
	}

	group_list = SMB_MALLOC_ARRAY(struct winbindd_gr, num_groups);
	if (!group_list) {
		request_error(state);
		return;
	}
	/* will be freed by process_request() */
	state->response.extra_data.data = group_list;

	memset(state->response.extra_data.data, '\0',
		num_groups * sizeof(struct winbindd_gr) );

	state->response.data.num_entries = 0;

	if (!state->getgrent_initialized)
		winbindd_setgrent_internal(state);

	if (!(ent = state->getgrent_state)) {
		request_error(state);
		return;
	}

	/* Start sending back groups */

	for (group_list_ndx = 0; group_list_ndx < num_groups; ) {
		struct acct_info *name_list = NULL;
		fstring domain_group_name;
		uint32 result;
		gid_t group_gid;
		size_t gr_mem_len;
		char *gr_mem;
		DOM_SID group_sid;
		struct winbindd_domain *domain;

		/* Do we need to fetch another chunk of groups? */

	tryagain:

		DEBUG(10, ("entry_index = %d, num_entries = %d\n",
			   ent->sam_entry_index, ent->num_sam_entries));

		if (ent->num_sam_entries == ent->sam_entry_index) {

			while(ent && !get_sam_group_entries(ent)) {
				struct getent_state *next_ent;

				DEBUG(10, ("freeing state info for domain %s\n",
					   ent->domain_name));

				/* Free state information for this domain */

				SAFE_FREE(ent->sam_entries);

				next_ent = ent->next;
				DLIST_REMOVE(state->getgrent_state, ent);

				SAFE_FREE(ent);
				ent = next_ent;
			}

			/* No more domains */

			if (!ent)
                                break;
		}

		name_list = (struct acct_info *)ent->sam_entries;

		if (!(domain = find_domain_from_name(ent->domain_name))) {
			DEBUG(3, ("No such domain %s in winbindd_getgrent\n",
				  ent->domain_name));
			result = False;
			goto done;
		}

		/* Lookup group info */

		sid_copy(&group_sid, &domain->sid);
		sid_append_rid(&group_sid, name_list[ent->sam_entry_index].rid);

		if (!NT_STATUS_IS_OK(idmap_sid_to_gid(domain->have_idmap_config
						      ? domain->name : "",
						      &group_sid, &group_gid)))
		{
			union unid_t id;
			enum lsa_SidType type;

			DEBUG(10, ("SID %s not in idmap\n",
				   sid_string_dbg(&group_sid)));

			if (!pdb_sid_to_id(&group_sid, &id, &type)) {
				DEBUG(1,("could not look up gid for group %s\n",
					 name_list[ent->sam_entry_index].acct_name));
				ent->sam_entry_index++;
				goto tryagain;
			}

			if ((type != SID_NAME_DOM_GRP) &&
			    (type != SID_NAME_ALIAS) &&
			    (type != SID_NAME_WKN_GRP)) {
				DEBUG(1, ("Group %s is a %s, not a group\n",
					  sid_type_lookup(type),
					  name_list[ent->sam_entry_index].acct_name));
				ent->sam_entry_index++;
				goto tryagain;
			}
			group_gid = id.gid;
		}

		DEBUG(10, ("got gid %lu for group %lu\n",
			   (unsigned long)group_gid,
			   (unsigned long)name_list[ent->sam_entry_index].rid));

		/* Fill in group entry */

		fill_domain_username(domain_group_name, ent->domain_name,
			 name_list[ent->sam_entry_index].acct_name, True);

		result = fill_grent(state->mem_ctx, &group_list[group_list_ndx],
				    ent->domain_name,
				    name_list[ent->sam_entry_index].acct_name,
				    group_gid);

		/* Fill in group membership entry */

		if (result) {
			size_t num_gr_mem = 0;
			DOM_SID member_sid;
			group_list[group_list_ndx].num_gr_mem = 0;
			gr_mem = NULL;
			gr_mem_len = 0;

			/* Get group membership */
			if (state->request.cmd == WINBINDD_GETGRLST) {
				result = True;
			} else {
				sid_copy(&member_sid, &domain->sid);
				sid_append_rid(&member_sid, name_list[ent->sam_entry_index].rid);
				result = fill_grent_mem(
					domain,
					NULL,
					&member_sid,
					SID_NAME_DOM_GRP,
					&num_gr_mem,
					&gr_mem, &gr_mem_len);

				group_list[group_list_ndx].num_gr_mem = (uint32)num_gr_mem;
			}
		}

		if (result) {
			/* Append to group membership list */
			gr_mem_list = (char *)SMB_REALLOC(
				gr_mem_list, gr_mem_list_len + gr_mem_len);

			if (!gr_mem_list &&
			    (group_list[group_list_ndx].num_gr_mem != 0)) {
				DEBUG(0, ("out of memory\n"));
				gr_mem_list_len = 0;
				break;
			}

			DEBUG(10, ("list_len = %d, mem_len = %u\n",
				   gr_mem_list_len, (unsigned int)gr_mem_len));

			memcpy(&gr_mem_list[gr_mem_list_len], gr_mem,
			       gr_mem_len);

			SAFE_FREE(gr_mem);

			group_list[group_list_ndx].gr_mem_ofs =
				gr_mem_list_len;

			gr_mem_list_len += gr_mem_len;
		}

		ent->sam_entry_index++;

		/* Add group to return list */

		if (result) {

			DEBUG(10, ("adding group num_entries = %d\n",
				   state->response.data.num_entries));

			group_list_ndx++;
			state->response.data.num_entries++;

			state->response.length +=
				sizeof(struct winbindd_gr);

		} else {
			DEBUG(0, ("could not lookup domain group %s\n",
				  domain_group_name));
		}
	}

	/* Copy the list of group memberships to the end of the extra data */

	if (group_list_ndx == 0)
		goto done;

	state->response.extra_data.data = SMB_REALLOC(
		state->response.extra_data.data,
		group_list_ndx * sizeof(struct winbindd_gr) + gr_mem_list_len);

	if (!state->response.extra_data.data) {
		DEBUG(0, ("out of memory\n"));
		group_list_ndx = 0;
		SAFE_FREE(gr_mem_list);
		request_error(state);
		return;
	}

	memcpy(&((char *)state->response.extra_data.data)
	       [group_list_ndx * sizeof(struct winbindd_gr)],
	       gr_mem_list, gr_mem_list_len);

	state->response.length += gr_mem_list_len;

	DEBUG(10, ("returning %d groups, length = %d\n",
		   group_list_ndx, gr_mem_list_len));

	/* Out of domains */

 done:

       	SAFE_FREE(gr_mem_list);

	if (group_list_ndx > 0)
		request_ok(state);
	else
		request_error(state);
}

/* List domain groups without mapping to unix ids */
void winbindd_list_groups(struct winbindd_cli_state *state)
{
	winbindd_list_ent(state, LIST_GROUPS);
}

/* Get user supplementary groups.  This is much quicker than trying to
   invert the groups database.  We merge the groups from the gids and
   other_sids info3 fields as trusted domain, universal group
   memberships, and nested groups (win2k native mode only) are not
   returned by the getgroups RPC call but are present in the info3. */

struct getgroups_state {
	struct winbindd_cli_state *state;
	struct winbindd_domain *domain;
	char *domname;
	char *username;
	DOM_SID user_sid;

	const DOM_SID *token_sids;
	size_t i, num_token_sids;

	gid_t *token_gids;
	size_t num_token_gids;
};

static void getgroups_usersid_recv(void *private_data, bool success,
				   const DOM_SID *sid, enum lsa_SidType type);
static void getgroups_tokensids_recv(void *private_data, bool success,
				     DOM_SID *token_sids, size_t num_token_sids);
static void getgroups_sid2gid_recv(void *private_data, bool success, gid_t gid);

void winbindd_getgroups(struct winbindd_cli_state *state)
{
	struct getgroups_state *s;
	char *real_name = NULL;
	NTSTATUS nt_status = NT_STATUS_UNSUCCESSFUL;

	/* Ensure null termination */
	state->request.data.username
		[sizeof(state->request.data.username)-1]='\0';

	DEBUG(3, ("[%5lu]: getgroups %s\n", (unsigned long)state->pid,
		  state->request.data.username));

	/* Parse domain and username */

	s = TALLOC_P(state->mem_ctx, struct getgroups_state);
	if (s == NULL) {
		DEBUG(0, ("talloc failed\n"));
		request_error(state);
		return;
	}

	s->state = state;

	nt_status = normalize_name_unmap(state->mem_ctx,
					 state->request.data.username,
					 &real_name);

	/* Reset the real_name pointer if we didn't do anything
	   productive in the above call */
	if (!NT_STATUS_IS_OK(nt_status) &&
	    !NT_STATUS_EQUAL(nt_status, NT_STATUS_FILE_RENAMED))
	{
		real_name = state->request.data.username;
	}

	if (!parse_domain_user_talloc(state->mem_ctx, real_name,
				      &s->domname, &s->username)) {
		DEBUG(5, ("Could not parse domain user: %s\n",
			  real_name));

		/* error out if we do not have nested group support */

		if ( !lp_winbind_nested_groups() ) {
			request_error(state);
			return;
		}

		s->domname = talloc_strdup(state->mem_ctx,
					   get_global_sam_name());
		s->username = talloc_strdup(state->mem_ctx,
					    state->request.data.username);
	}

	/* Get info for the domain (either by short domain name or
	   DNS name in the case of a UPN) */

	s->domain = find_domain_from_name_noinit(s->domname);
	if (!s->domain) {
		char *p = strchr(s->username, '@');

		if (p) {
			s->domain = find_domain_from_name_noinit(p+1);
		}

	}

	if (s->domain == NULL) {
		DEBUG(7, ("could not find domain entry for domain %s\n",
			  s->domname));
		request_error(state);
		return;
	}

	if ( s->domain->primary && lp_winbind_trusted_domains_only()) {
		DEBUG(7,("winbindd_getgroups: My domain -- rejecting "
			 "getgroups() for %s\\%s.\n", s->domname,
			 s->username));
		request_error(state);
		return;
	}

	/* Get rid and name type from name.  The following costs 1 packet */

	winbindd_lookupname_async(state->mem_ctx,
				  s->domname, s->username,
				  getgroups_usersid_recv,
				  WINBINDD_GETGROUPS, s);
}

static void getgroups_usersid_recv(void *private_data, bool success,
				   const DOM_SID *sid, enum lsa_SidType type)
{
	struct getgroups_state *s =
		(struct getgroups_state *)private_data;

	if ((!success) ||
	    ((type != SID_NAME_USER) && (type != SID_NAME_COMPUTER))) {
		request_error(s->state);
		return;
	}

	sid_copy(&s->user_sid, sid);

	winbindd_gettoken_async(s->state->mem_ctx, &s->user_sid,
				getgroups_tokensids_recv, s);
}

static void getgroups_tokensids_recv(void *private_data, bool success,
				     DOM_SID *token_sids, size_t num_token_sids)
{
	struct getgroups_state *s =
		(struct getgroups_state *)private_data;

	/* We need at least the user sid and the primary group in the token,
	 * otherwise it's an error */

	if ((!success) || (num_token_sids < 2)) {
		request_error(s->state);
		return;
	}

	s->token_sids = token_sids;
	s->num_token_sids = num_token_sids;
	s->i = 0;

	s->token_gids = NULL;
	s->num_token_gids = 0;

	getgroups_sid2gid_recv(s, False, 0);
}

static void getgroups_sid2gid_recv(void *private_data, bool success, gid_t gid)
{
	struct getgroups_state *s =
		(struct getgroups_state *)private_data;

	if (success) {
		if (!add_gid_to_array_unique(s->state->mem_ctx, gid,
					&s->token_gids,
					&s->num_token_gids)) {
			return;
		}
	}

	if (s->i < s->num_token_sids) {
		const DOM_SID *sid = &s->token_sids[s->i];
		s->i += 1;

		if (sid_equal(sid, &s->user_sid)) {
			getgroups_sid2gid_recv(s, False, 0);
			return;
		}

		winbindd_sid2gid_async(s->state->mem_ctx, sid,
				       getgroups_sid2gid_recv, s);
		return;
	}

	s->state->response.data.num_entries = s->num_token_gids;
	if (s->num_token_gids) {
		/* s->token_gids are talloced */
		s->state->response.extra_data.data =
			smb_xmemdup(s->token_gids,
					s->num_token_gids * sizeof(gid_t));
		s->state->response.length += s->num_token_gids * sizeof(gid_t);
	}
	request_ok(s->state);
}

/* Get user supplementary sids. This is equivalent to the
   winbindd_getgroups() function but it involves a SID->SIDs mapping
   rather than a NAME->SID->SIDS->GIDS mapping, which means we avoid
   idmap. This call is designed to be used with applications that need
   to do ACL evaluation themselves. Note that the cached info3 data is
   not used

   this function assumes that the SID that comes in is a user SID. If
   you pass in another type of SID then you may get unpredictable
   results.
*/

static void getusersids_recv(void *private_data, bool success, DOM_SID *sids,
			     size_t num_sids);

void winbindd_getusersids(struct winbindd_cli_state *state)
{
	DOM_SID *user_sid;

	/* Ensure null termination */
	state->request.data.sid[sizeof(state->request.data.sid)-1]='\0';

	user_sid = TALLOC_P(state->mem_ctx, DOM_SID);
	if (user_sid == NULL) {
		DEBUG(1, ("talloc failed\n"));
		request_error(state);
		return;
	}

	if (!string_to_sid(user_sid, state->request.data.sid)) {
		DEBUG(1, ("Could not get convert sid %s from string\n",
			  state->request.data.sid));
		request_error(state);
		return;
	}

	winbindd_gettoken_async(state->mem_ctx, user_sid, getusersids_recv,
				state);
}

static void getusersids_recv(void *private_data, bool success, DOM_SID *sids,
			     size_t num_sids)
{
	struct winbindd_cli_state *state =
		(struct winbindd_cli_state *)private_data;
	char *ret = NULL;
	unsigned ofs, ret_size = 0;
	size_t i;

	if (!success) {
		request_error(state);
		return;
	}

	/* work out the response size */
	for (i = 0; i < num_sids; i++) {
		fstring s;
		sid_to_fstring(s, &sids[i]);
		ret_size += strlen(s) + 1;
	}

	/* build the reply */
	ret = (char *)SMB_MALLOC(ret_size);
	if (!ret) {
		DEBUG(0, ("malloc failed\n"));
		request_error(state);
		return;
	}
	ofs = 0;
	for (i = 0; i < num_sids; i++) {
		fstring s;
		sid_to_fstring(s, &sids[i]);
		safe_strcpy(ret + ofs, s, ret_size - ofs - 1);
		ofs += strlen(ret+ofs) + 1;
	}

	/* Send data back to client */
	state->response.data.num_entries = num_sids;
	state->response.extra_data.data = ret;
	state->response.length += ret_size;
	request_ok(state);
}

void winbindd_getuserdomgroups(struct winbindd_cli_state *state)
{
	DOM_SID user_sid;
	struct winbindd_domain *domain;

	/* Ensure null termination */
	state->request.data.sid[sizeof(state->request.data.sid)-1]='\0';

	if (!string_to_sid(&user_sid, state->request.data.sid)) {
		DEBUG(1, ("Could not get convert sid %s from string\n",
			  state->request.data.sid));
		request_error(state);
		return;
	}

	/* Get info for the domain */
	if ((domain = find_domain_from_sid_noinit(&user_sid)) == NULL) {
		DEBUG(0,("could not find domain entry for sid %s\n",
			 sid_string_dbg(&user_sid)));
		request_error(state);
		return;
	}

	sendto_domain(state, domain);
}

enum winbindd_result winbindd_dual_getuserdomgroups(struct winbindd_domain *domain,
						    struct winbindd_cli_state *state)
{
	DOM_SID user_sid;
	NTSTATUS status;

	char *sidstring;
	ssize_t len;
	DOM_SID *groups;
	uint32 num_groups;

	/* Ensure null termination */
	state->request.data.sid[sizeof(state->request.data.sid)-1]='\0';

	if (!string_to_sid(&user_sid, state->request.data.sid)) {
		DEBUG(1, ("Could not get convert sid %s from string\n",
			  state->request.data.sid));
		return WINBINDD_ERROR;
	}

	status = domain->methods->lookup_usergroups(domain, state->mem_ctx,
						    &user_sid, &num_groups,
						    &groups);
	if (!NT_STATUS_IS_OK(status))
		return WINBINDD_ERROR;

	if (num_groups == 0) {
		state->response.data.num_entries = 0;
		state->response.extra_data.data = NULL;
		return WINBINDD_OK;
	}

	if (!print_sidlist(state->mem_ctx,
			   groups, num_groups,
			   &sidstring, &len)) {
		DEBUG(0, ("talloc failed\n"));
		return WINBINDD_ERROR;
	}

	state->response.extra_data.data = SMB_STRDUP(sidstring);
	if (!state->response.extra_data.data) {
		return WINBINDD_ERROR;
	}
	state->response.length += len+1;
	state->response.data.num_entries = num_groups;

	return WINBINDD_OK;
}

void winbindd_getsidaliases(struct winbindd_cli_state *state)
{
	DOM_SID domain_sid;
	struct winbindd_domain *domain;

	/* Ensure null termination */
	state->request.data.sid[sizeof(state->request.data.sid)-1]='\0';

	if (!string_to_sid(&domain_sid, state->request.data.sid)) {
		DEBUG(1, ("Could not get convert sid %s from string\n",
			  state->request.data.sid));
		request_error(state);
		return;
	}

	/* Get info for the domain */
	if ((domain = find_domain_from_sid_noinit(&domain_sid)) == NULL) {
		DEBUG(0,("could not find domain entry for sid %s\n",
			 sid_string_dbg(&domain_sid)));
		request_error(state);
		return;
	}

	sendto_domain(state, domain);
}

enum winbindd_result winbindd_dual_getsidaliases(struct winbindd_domain *domain,
						 struct winbindd_cli_state *state)
{
	DOM_SID *sids = NULL;
	size_t num_sids = 0;
	char *sidstr = NULL;
	ssize_t len;
	size_t i;
	uint32 num_aliases;
	uint32 *alias_rids;
	NTSTATUS result;

	DEBUG(3, ("[%5lu]: getsidaliases\n", (unsigned long)state->pid));

	sidstr = state->request.extra_data.data;
	if (sidstr == NULL) {
		sidstr = talloc_strdup(state->mem_ctx, "\n"); /* No SID */
		if (!sidstr) {
			DEBUG(0, ("Out of memory\n"));
			return WINBINDD_ERROR;
		}
	}

	DEBUG(10, ("Sidlist: %s\n", sidstr));

	if (!parse_sidlist(state->mem_ctx, sidstr, &sids, &num_sids)) {
		DEBUG(0, ("Could not parse SID list: %s\n", sidstr));
		return WINBINDD_ERROR;
	}

	num_aliases = 0;
	alias_rids = NULL;

	result = domain->methods->lookup_useraliases(domain,
						     state->mem_ctx,
						     num_sids, sids,
						     &num_aliases,
						     &alias_rids);

	if (!NT_STATUS_IS_OK(result)) {
		DEBUG(3, ("Could not lookup_useraliases: %s\n",
			  nt_errstr(result)));
		return WINBINDD_ERROR;
	}

	num_sids = 0;
	sids = NULL;
	sidstr = NULL;

	DEBUG(10, ("Got %d aliases\n", num_aliases));

	for (i=0; i<num_aliases; i++) {
		DOM_SID sid;
		DEBUGADD(10, (" rid %d\n", alias_rids[i]));
		sid_copy(&sid, &domain->sid);
		sid_append_rid(&sid, alias_rids[i]);
		result = add_sid_to_array(state->mem_ctx, &sid, &sids,
					  &num_sids);
		if (!NT_STATUS_IS_OK(result)) {
			return WINBINDD_ERROR;
		}
	}


	if (!print_sidlist(state->mem_ctx, sids, num_sids, &sidstr, &len)) {
		DEBUG(0, ("Could not print_sidlist\n"));
		state->response.extra_data.data = NULL;
		return WINBINDD_ERROR;
	}

	state->response.extra_data.data = NULL;

	if (sidstr) {
		state->response.extra_data.data = SMB_STRDUP(sidstr);
		if (!state->response.extra_data.data) {
			DEBUG(0, ("Out of memory\n"));
			return WINBINDD_ERROR;
		}
		DEBUG(10, ("aliases_list: %s\n",
			   (char *)state->response.extra_data.data));
		state->response.length += len+1;
		state->response.data.num_entries = num_sids;
	}

	return WINBINDD_OK;
}


