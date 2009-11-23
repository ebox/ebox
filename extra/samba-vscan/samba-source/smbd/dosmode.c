/* 
   Unix SMB/CIFS implementation.
   dos mode handling functions
   Copyright (C) Andrew Tridgell 1992-1998
   Copyright (C) James Peach 2006
   
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

static int set_sparse_flag(const SMB_STRUCT_STAT * const sbuf)
{
#if defined (HAVE_STAT_ST_BLOCKS) && defined(STAT_ST_BLOCKSIZE)
	if (sbuf->st_size > sbuf->st_blocks * (SMB_OFF_T)STAT_ST_BLOCKSIZE) {
		return FILE_ATTRIBUTE_SPARSE;
	}
#endif
	return 0;
}

static int set_link_read_only_flag(const SMB_STRUCT_STAT *const sbuf)
{
#ifdef S_ISLNK
#if LINKS_READ_ONLY
	if (S_ISLNK(sbuf->st_mode) && S_ISDIR(sbuf->st_mode))
		return aRONLY;
#endif
#endif
	return 0;
}

/****************************************************************************
 Change a dos mode to a unix mode.
    Base permission for files:
         if creating file and inheriting (i.e. parent_dir != NULL)
           apply read/write bits from parent directory.
         else   
           everybody gets read bit set
         dos readonly is represented in unix by removing everyone's write bit
         dos archive is represented in unix by the user's execute bit
         dos system is represented in unix by the group's execute bit
         dos hidden is represented in unix by the other's execute bit
         if !inheriting {
           Then apply create mask,
           then add force bits.
         }
    Base permission for directories:
         dos directory is represented in unix by unix's dir bit and the exec bit
         if !inheriting {
           Then apply create mask,
           then add force bits.
         }
****************************************************************************/

mode_t unix_mode(connection_struct *conn, int dosmode, const char *fname,
		 const char *inherit_from_dir)
{
	mode_t result = (S_IRUSR | S_IRGRP | S_IROTH | S_IWUSR | S_IWGRP | S_IWOTH);
	mode_t dir_mode = 0; /* Mode of the inherit_from directory if
			      * inheriting. */

	if (!lp_store_dos_attributes(SNUM(conn)) && IS_DOS_READONLY(dosmode)) {
		result &= ~(S_IWUSR | S_IWGRP | S_IWOTH);
	}

	if (fname && (inherit_from_dir != NULL)
	    && lp_inherit_perms(SNUM(conn))) {
		SMB_STRUCT_STAT sbuf;

		DEBUG(2, ("unix_mode(%s) inheriting from %s\n", fname,
			  inherit_from_dir));
		if (SMB_VFS_STAT(conn, inherit_from_dir, &sbuf) != 0) {
			DEBUG(4,("unix_mode(%s) failed, [dir %s]: %s\n", fname,
				 inherit_from_dir, strerror(errno)));
			return(0);      /* *** shouldn't happen! *** */
		}

		/* Save for later - but explicitly remove setuid bit for safety. */
		dir_mode = sbuf.st_mode & ~S_ISUID;
		DEBUG(2,("unix_mode(%s) inherit mode %o\n",fname,(int)dir_mode));
		/* Clear "result" */
		result = 0;
	} 

	if (IS_DOS_DIR(dosmode)) {
		/* We never make directories read only for the owner as under DOS a user
		can always create a file in a read-only directory. */
		result |= (S_IFDIR | S_IWUSR);

		if (dir_mode) {
			/* Inherit mode of parent directory. */
			result |= dir_mode;
		} else {
			/* Provisionally add all 'x' bits */
			result |= (S_IXUSR | S_IXGRP | S_IXOTH);                 

			/* Apply directory mask */
			result &= lp_dir_mask(SNUM(conn));
			/* Add in force bits */
			result |= lp_force_dir_mode(SNUM(conn));
		}
	} else { 
		if (lp_map_archive(SNUM(conn)) && IS_DOS_ARCHIVE(dosmode))
			result |= S_IXUSR;

		if (lp_map_system(SNUM(conn)) && IS_DOS_SYSTEM(dosmode))
			result |= S_IXGRP;
 
		if (lp_map_hidden(SNUM(conn)) && IS_DOS_HIDDEN(dosmode))
			result |= S_IXOTH;  

		if (dir_mode) {
			/* Inherit 666 component of parent directory mode */
			result |= dir_mode & (S_IRUSR | S_IRGRP | S_IROTH | S_IWUSR | S_IWGRP | S_IWOTH);
		} else {
			/* Apply mode mask */
			result &= lp_create_mask(SNUM(conn));
			/* Add in force bits */
			result |= lp_force_create_mode(SNUM(conn));
		}
	}

	DEBUG(3,("unix_mode(%s) returning 0%o\n",fname,(int)result ));
	return(result);
}

/****************************************************************************
 Change a unix mode to a dos mode.
****************************************************************************/

static uint32 dos_mode_from_sbuf(connection_struct *conn, const char *path, SMB_STRUCT_STAT *sbuf)
{
	int result = 0;
	enum mapreadonly_options ro_opts = (enum mapreadonly_options)lp_map_readonly(SNUM(conn));

	if (ro_opts == MAP_READONLY_YES) {
		/* Original Samba method - map inverse of user "w" bit. */
		if ((sbuf->st_mode & S_IWUSR) == 0) {
			result |= aRONLY;
		}
	} else if (ro_opts == MAP_READONLY_PERMISSIONS) {
		/* Check actual permissions for read-only. */
		if (!can_write_to_file(conn, path, sbuf)) {
			result |= aRONLY;
		}
	} /* Else never set the readonly bit. */

	if (MAP_ARCHIVE(conn) && ((sbuf->st_mode & S_IXUSR) != 0))
		result |= aARCH;

	if (MAP_SYSTEM(conn) && ((sbuf->st_mode & S_IXGRP) != 0))
		result |= aSYSTEM;
	
	if (MAP_HIDDEN(conn) && ((sbuf->st_mode & S_IXOTH) != 0))
		result |= aHIDDEN;   
  
	if (S_ISDIR(sbuf->st_mode))
		result = aDIR | (result & aRONLY);

	result |= set_sparse_flag(sbuf);
	result |= set_link_read_only_flag(sbuf);

	DEBUG(8,("dos_mode_from_sbuf returning "));

	if (result & aHIDDEN) DEBUG(8, ("h"));
	if (result & aRONLY ) DEBUG(8, ("r"));
	if (result & aSYSTEM) DEBUG(8, ("s"));
	if (result & aDIR   ) DEBUG(8, ("d"));
	if (result & aARCH  ) DEBUG(8, ("a"));
	
	DEBUG(8,("\n"));
	return result;
}

/****************************************************************************
 Get DOS attributes from an EA.
****************************************************************************/

static bool get_ea_dos_attribute(connection_struct *conn, const char *path,SMB_STRUCT_STAT *sbuf, uint32 *pattr)
{
	ssize_t sizeret;
	fstring attrstr;
	unsigned int dosattr;

	if (!lp_store_dos_attributes(SNUM(conn))) {
		return False;
	}

	/* Don't reset pattr to zero as we may already have filename-based attributes we
	   need to preserve. */

	sizeret = SMB_VFS_GETXATTR(conn, path, SAMBA_XATTR_DOS_ATTRIB, attrstr, sizeof(attrstr));
	if (sizeret == -1) {
		if (errno == ENOSYS
#if defined(ENOTSUP)
			|| errno == ENOTSUP) {
#else
				) {
#endif
			DEBUG(1,("get_ea_dos_attributes: Cannot get attribute from EA on file %s: Error = %s\n",
				path, strerror(errno) ));
			set_store_dos_attributes(SNUM(conn), False);
		}
		return False;
	}
	/* Null terminate string. */
	attrstr[sizeret] = 0;
	DEBUG(10,("get_ea_dos_attribute: %s attrstr = %s\n", path, attrstr));

	if (sizeret < 2 || attrstr[0] != '0' || attrstr[1] != 'x' ||
			sscanf(attrstr, "%x", &dosattr) != 1) {
		DEBUG(1,("get_ea_dos_attributes: Badly formed DOSATTRIB on file %s - %s\n", path, attrstr));
                return False;
        }

	if (S_ISDIR(sbuf->st_mode)) {
		dosattr |= aDIR;
	}
	*pattr = (uint32)(dosattr & SAMBA_ATTRIBUTES_MASK);

	DEBUG(8,("get_ea_dos_attribute returning (0x%x)", dosattr));

	if (dosattr & aHIDDEN) DEBUG(8, ("h"));
	if (dosattr & aRONLY ) DEBUG(8, ("r"));
	if (dosattr & aSYSTEM) DEBUG(8, ("s"));
	if (dosattr & aDIR   ) DEBUG(8, ("d"));
	if (dosattr & aARCH  ) DEBUG(8, ("a"));
	
	DEBUG(8,("\n"));

	return True;
}

/****************************************************************************
 Set DOS attributes in an EA.
****************************************************************************/

static bool set_ea_dos_attribute(connection_struct *conn, const char *path, SMB_STRUCT_STAT *sbuf, uint32 dosmode)
{
	fstring attrstr;
	files_struct *fsp = NULL;
	bool ret = False;

	if (!lp_store_dos_attributes(SNUM(conn))) {
		return False;
	}

	snprintf(attrstr, sizeof(attrstr)-1, "0x%x", dosmode & SAMBA_ATTRIBUTES_MASK);
	if (SMB_VFS_SETXATTR(conn, path, SAMBA_XATTR_DOS_ATTRIB, attrstr, strlen(attrstr), 0) == -1) {
		if((errno != EPERM) && (errno != EACCES)) {
			if (errno == ENOSYS
#if defined(ENOTSUP)
				|| errno == ENOTSUP) {
#else
				) {
#endif
				DEBUG(1,("set_ea_dos_attributes: Cannot set attribute EA on file %s: Error = %s\n",
					path, strerror(errno) ));
				set_store_dos_attributes(SNUM(conn), False);
			}
			return False;
		}

		/* We want DOS semantics, ie allow non owner with write permission to change the
			bits on a file. Just like file_ntimes below.
		*/

		/* Check if we have write access. */
		if(!CAN_WRITE(conn) || !lp_dos_filemode(SNUM(conn)))
			return False;

		/*
		 * We need to open the file with write access whilst
		 * still in our current user context. This ensures we
		 * are not violating security in doing the setxattr.
		 */

		if (!NT_STATUS_IS_OK(open_file_fchmod(NULL, conn, path, sbuf,
						      &fsp)))
			return ret;
		become_root();
		if (SMB_VFS_SETXATTR(conn, path, SAMBA_XATTR_DOS_ATTRIB, attrstr, strlen(attrstr), 0) == 0) {
			ret = True;
		}
		unbecome_root();
		close_file_fchmod(NULL, fsp);
		return ret;
	}
	DEBUG(10,("set_ea_dos_attribute: set EA %s on file %s\n", attrstr, path));
	return True;
}

/****************************************************************************
 Change a unix mode to a dos mode for an ms dfs link.
****************************************************************************/

uint32 dos_mode_msdfs(connection_struct *conn, const char *path,SMB_STRUCT_STAT *sbuf)
{
	uint32 result = 0;

	DEBUG(8,("dos_mode_msdfs: %s\n", path));

	if (!VALID_STAT(*sbuf)) {
		return 0;
	}

	/* First do any modifications that depend on the path name. */
	/* hide files with a name starting with a . */
	if (lp_hide_dot_files(SNUM(conn))) {
		const char *p = strrchr_m(path,'/');
		if (p) {
			p++;
		} else {
			p = path;
		}

		/* Only . and .. are not hidden. */
		if (p[0] == '.' && !((p[1] == '\0') ||
				(p[1] == '.' && p[2] == '\0'))) {
			result |= aHIDDEN;
		}
	}
	
	result |= dos_mode_from_sbuf(conn, path, sbuf);

	/* Optimization : Only call is_hidden_path if it's not already
	   hidden. */
	if (!(result & aHIDDEN) && IS_HIDDEN_PATH(conn,path)) {
		result |= aHIDDEN;
	}

	DEBUG(8,("dos_mode_msdfs returning "));

	if (result & aHIDDEN) DEBUG(8, ("h"));
	if (result & aRONLY ) DEBUG(8, ("r"));
	if (result & aSYSTEM) DEBUG(8, ("s"));
	if (result & aDIR   ) DEBUG(8, ("d"));
	if (result & aARCH  ) DEBUG(8, ("a"));
	if (result & FILE_ATTRIBUTE_SPARSE ) DEBUG(8, ("[sparse]"));
	
	DEBUG(8,("\n"));

	return(result);
}

#ifdef HAVE_STAT_DOS_FLAGS
/****************************************************************************
 Convert dos attributes (FILE_ATTRIBUTE_*) to dos stat flags (UF_*)
****************************************************************************/

int dos_attributes_to_stat_dos_flags(uint32_t dosmode)
{
	uint32_t dos_stat_flags = 0;

	if (dosmode & aARCH)
		dos_stat_flags |= UF_DOS_ARCHIVE;
	if (dosmode & aHIDDEN)
		dos_stat_flags |= UF_DOS_HIDDEN;
	if (dosmode & aRONLY)
		dos_stat_flags |= UF_DOS_RO;
	if (dosmode & aSYSTEM)
		dos_stat_flags |= UF_DOS_SYSTEM;
	if (dosmode & FILE_ATTRIBUTE_NONINDEXED)
		dos_stat_flags |= UF_DOS_NOINDEX;

	return dos_stat_flags;
}

/****************************************************************************
 Gets DOS attributes, accessed via st_flags in the stat struct.
****************************************************************************/

static bool get_stat_dos_flags(connection_struct *conn,
			       const char *fname,
			       const SMB_STRUCT_STAT *sbuf,
			       uint32_t *dosmode)
{
	SMB_ASSERT(sbuf && VALID_STAT(*sbuf));
	SMB_ASSERT(dosmode);

	if (!lp_store_dos_attributes(SNUM(conn))) {
		return false;
	}

	DEBUG(5, ("Getting stat dos attributes for %s.\n", fname));

	if (sbuf->st_flags & UF_DOS_ARCHIVE)
		*dosmode |= aARCH;
	if (sbuf->st_flags & UF_DOS_HIDDEN)
		*dosmode |= aHIDDEN;
	if (sbuf->st_flags & UF_DOS_RO)
		*dosmode |= aRONLY;
	if (sbuf->st_flags & UF_DOS_SYSTEM)
		*dosmode |= aSYSTEM;
	if (sbuf->st_flags & UF_DOS_NOINDEX)
		*dosmode |= FILE_ATTRIBUTE_NONINDEXED;
	if (S_ISDIR(sbuf->st_mode))
		*dosmode |= aDIR;

	*dosmode |= set_sparse_flag(sbuf);
	*dosmode |= set_link_read_only_flag(sbuf);

	return true;
}

/****************************************************************************
 Sets DOS attributes, stored in st_flags of the inode.
****************************************************************************/

static bool set_stat_dos_flags(connection_struct *conn,
				const char *fname,
				SMB_STRUCT_STAT *sbuf,
				uint32_t dosmode,
				bool *attributes_changed)
{
	uint32_t new_flags = 0;
	int error = 0;

	SMB_ASSERT(sbuf && VALID_STAT(*sbuf));
	SMB_ASSERT(attributes_changed);

	*attributes_changed = false;

	if (!lp_store_dos_attributes(SNUM(conn))) {
		return false;
	}

	DEBUG(5, ("Setting stat dos attributes for %s.\n", fname));

	new_flags = (sbuf->st_flags & ~UF_DOS_FLAGS) |
		     dos_attributes_to_stat_dos_flags(dosmode);

	/* Return early if no flags changed. */
	if (new_flags == sbuf->st_flags)
		return true;

	DEBUG(5, ("Setting stat dos attributes=0x%x, prev=0x%x\n", new_flags,
		  sbuf->st_flags));

	/* Set new flags with chflags. */
	error = SMB_VFS_CHFLAGS(conn, fname, new_flags);
	if (error) {
		DEBUG(0, ("Failed setting new stat dos attributes (0x%x) on "
			  "file %s! errno=%d\n", new_flags, fname, errno));
		return false;
	}

	*attributes_changed = true;
	return true;
}
#endif /* HAVE_STAT_DOS_FLAGS */

/****************************************************************************
 Change a unix mode to a dos mode.
****************************************************************************/

uint32 dos_mode(connection_struct *conn, const char *path,SMB_STRUCT_STAT *sbuf)
{
	uint32 result = 0;
	bool offline, used_stat_dos_flags = false;

	DEBUG(8,("dos_mode: %s\n", path));

	if (!VALID_STAT(*sbuf)) {
		return 0;
	}

	/* First do any modifications that depend on the path name. */
	/* hide files with a name starting with a . */
	if (lp_hide_dot_files(SNUM(conn))) {
		const char *p = strrchr_m(path,'/');
		if (p) {
			p++;
		} else {
			p = path;
		}

		/* Only . and .. are not hidden. */
		if (p[0] == '.' && !((p[1] == '\0') ||
				(p[1] == '.' && p[2] == '\0'))) {
			result |= aHIDDEN;
		}
	}
	
#ifdef HAVE_STAT_DOS_FLAGS
	used_stat_dos_flags = get_stat_dos_flags(conn, path, sbuf, &result);
#endif
	if (!used_stat_dos_flags) {
		/* Get the DOS attributes from an EA by preference. */
		if (get_ea_dos_attribute(conn, path, sbuf, &result)) {
			result |= set_sparse_flag(sbuf);
		} else {
			result |= dos_mode_from_sbuf(conn, path, sbuf);
		}
	}

	
	offline = SMB_VFS_IS_OFFLINE(conn, path, sbuf);
	if (S_ISREG(sbuf->st_mode) && offline) {
		result |= FILE_ATTRIBUTE_OFFLINE;
	}

	/* Optimization : Only call is_hidden_path if it's not already
	   hidden. */
	if (!(result & aHIDDEN) && IS_HIDDEN_PATH(conn,path)) {
		result |= aHIDDEN;
	}

	DEBUG(8,("dos_mode returning "));

	if (result & aHIDDEN) DEBUG(8, ("h"));
	if (result & aRONLY ) DEBUG(8, ("r"));
	if (result & aSYSTEM) DEBUG(8, ("s"));
	if (result & aDIR   ) DEBUG(8, ("d"));
	if (result & aARCH  ) DEBUG(8, ("a"));
	if (result & FILE_ATTRIBUTE_SPARSE ) DEBUG(8, ("[sparse]"));
	
	DEBUG(8,("\n"));

	return(result);
}

/*******************************************************************
 chmod a file - but preserve some bits.
********************************************************************/

int file_set_dosmode(connection_struct *conn, const char *fname,
		     uint32 dosmode, SMB_STRUCT_STAT *st,
		     const char *parent_dir,
		     bool newfile)
{
	SMB_STRUCT_STAT st1;
	int mask=0;
	mode_t tmp;
	mode_t unixmode;
	int ret = -1, lret = -1;
	uint32_t old_mode;

	/* We only allow READONLY|HIDDEN|SYSTEM|DIRECTORY|ARCHIVE here. */
	dosmode &= (SAMBA_ATTRIBUTES_MASK | FILE_ATTRIBUTE_OFFLINE);

	DEBUG(10,("file_set_dosmode: setting dos mode 0x%x on file %s\n", dosmode, fname));

	if (st == NULL) {
		SET_STAT_INVALID(st1);
		st = &st1;
	}

	if (!VALID_STAT(*st)) {
		if (SMB_VFS_STAT(conn,fname,st))
			return(-1);
	}

	unixmode = st->st_mode;

	get_acl_group_bits(conn, fname, &st->st_mode);

	if (S_ISDIR(st->st_mode))
		dosmode |= aDIR;
	else
		dosmode &= ~aDIR;

	old_mode = dos_mode(conn,fname,st);
	
	if (dosmode & FILE_ATTRIBUTE_OFFLINE) {
		if (!(old_mode & FILE_ATTRIBUTE_OFFLINE)) {
			lret = SMB_VFS_SET_OFFLINE(conn, fname);
			if (lret == -1) {
				DEBUG(0, ("set_dos_mode: client has asked to set "
					  "FILE_ATTRIBUTE_OFFLINE to %s/%s but there was "
					  "an error while setting it or it is not supported.\n",
					  parent_dir, fname));
			}
		}
	}

	dosmode  &= ~FILE_ATTRIBUTE_OFFLINE;
	old_mode &= ~FILE_ATTRIBUTE_OFFLINE;

	if (old_mode == dosmode) {
		st->st_mode = unixmode;
		return(0);
	}

#ifdef HAVE_STAT_DOS_FLAGS
	{
		bool attributes_changed;

		if (set_stat_dos_flags(conn, fname, st, dosmode,
				       &attributes_changed))
		{
			if (!newfile && attributes_changed) {
				notify_fname(conn, NOTIFY_ACTION_MODIFIED,
				    FILE_NOTIFY_CHANGE_ATTRIBUTES, fname);
			}
			st->st_mode = unixmode;
			return 0;
		}
	}
#endif

	/* Store the DOS attributes in an EA by preference. */
	if (set_ea_dos_attribute(conn, fname, st, dosmode)) {
		if (!newfile) {
			notify_fname(conn, NOTIFY_ACTION_MODIFIED,
				FILE_NOTIFY_CHANGE_ATTRIBUTES, fname);
		}
		st->st_mode = unixmode;
		return 0;
	}

	unixmode = unix_mode(conn,dosmode,fname, parent_dir);

	/* preserve the s bits */
	mask |= (S_ISUID | S_ISGID);

	/* preserve the t bit */
#ifdef S_ISVTX
	mask |= S_ISVTX;
#endif

	/* possibly preserve the x bits */
	if (!MAP_ARCHIVE(conn))
		mask |= S_IXUSR;
	if (!MAP_SYSTEM(conn))
		mask |= S_IXGRP;
	if (!MAP_HIDDEN(conn))
		mask |= S_IXOTH;

	unixmode |= (st->st_mode & mask);

	/* if we previously had any r bits set then leave them alone */
	if ((tmp = st->st_mode & (S_IRUSR|S_IRGRP|S_IROTH))) {
		unixmode &= ~(S_IRUSR|S_IRGRP|S_IROTH);
		unixmode |= tmp;
	}

	/* if we previously had any w bits set then leave them alone 
		whilst adding in the new w bits, if the new mode is not rdonly */
	if (!IS_DOS_READONLY(dosmode)) {
		unixmode |= (st->st_mode & (S_IWUSR|S_IWGRP|S_IWOTH));
	}

	ret = SMB_VFS_CHMOD(conn, fname, unixmode);
	if (ret == 0) {
		if(!newfile || (lret != -1)) {
			notify_fname(conn, NOTIFY_ACTION_MODIFIED,
				     FILE_NOTIFY_CHANGE_ATTRIBUTES, fname);
		}
		st->st_mode = unixmode;
		return 0;
	}

	if((errno != EPERM) && (errno != EACCES))
		return -1;

	if(!lp_dos_filemode(SNUM(conn)))
		return -1;

	/* We want DOS semantics, ie allow non owner with write permission to change the
		bits on a file. Just like file_ntimes below.
	*/

	/* Check if we have write access. */
	if (CAN_WRITE(conn)) {
		/*
		 * We need to open the file with write access whilst
		 * still in our current user context. This ensures we
		 * are not violating security in doing the fchmod.
		 * This file open does *not* break any oplocks we are
		 * holding. We need to review this.... may need to
		 * break batch oplocks open by others. JRA.
		 */
		files_struct *fsp;
		if (!NT_STATUS_IS_OK(open_file_fchmod(NULL, conn, fname, st,
						      &fsp)))
			return -1;
		become_root();
		ret = SMB_VFS_FCHMOD(fsp, unixmode);
		unbecome_root();
		close_file_fchmod(NULL, fsp);
		if (!newfile) {
			notify_fname(conn, NOTIFY_ACTION_MODIFIED,
				FILE_NOTIFY_CHANGE_ATTRIBUTES, fname);
		}
		if (ret == 0) {
			st->st_mode = unixmode;
		}
	}

	return( ret );
}

/*******************************************************************
 Wrapper around the VFS ntimes that possibly allows DOS semantics rather
 than POSIX.
*******************************************************************/

int file_ntimes(connection_struct *conn, const char *fname,
		struct smb_file_time *ft)
{
	SMB_STRUCT_STAT sbuf;
	int ret = -1;

	errno = 0;
	ZERO_STRUCT(sbuf);

	DEBUG(6, ("file_ntime: actime: %s",
		  time_to_asc(convert_timespec_to_time_t(ft->atime))));
	DEBUG(6, ("file_ntime: modtime: %s",
		  time_to_asc(convert_timespec_to_time_t(ft->mtime))));
	DEBUG(6, ("file_ntime: createtime: %s",
		  time_to_asc(convert_timespec_to_time_t(ft->create_time))));

	/* Don't update the time on read-only shares */
	/* We need this as set_filetime (which can be called on
	   close and other paths) can end up calling this function
	   without the NEED_WRITE protection. Found by : 
	   Leo Weppelman <leo@wau.mis.ah.nl>
	*/

	if (!CAN_WRITE(conn)) {
		return 0;
	}

	if(SMB_VFS_NTIMES(conn, fname, ft) == 0) {
		return 0;
	}

	if((errno != EPERM) && (errno != EACCES)) {
		return -1;
	}

	if(!lp_dos_filetimes(SNUM(conn))) {
		return -1;
	}

	/* We have permission (given by the Samba admin) to
	   break POSIX semantics and allow a user to change
	   the time on a file they don't own but can write to
	   (as DOS does).
	 */

	/* Check if we have write access. */
	if (can_write_to_file(conn, fname, &sbuf)) {
		/* We are allowed to become root and change the filetime. */
		become_root();
		ret = SMB_VFS_NTIMES(conn, fname, ft);
		unbecome_root();
	}

	return ret;
}

/******************************************************************
 Force a "sticky" write time on a pathname. This will always be
 returned on all future write time queries and set on close.
******************************************************************/

bool set_sticky_write_time_path(connection_struct *conn, const char *fname,
			 struct file_id fileid, const struct timespec mtime)
{
	if (null_timespec(mtime)) {
		return true;
	}

	if (!set_sticky_write_time(fileid, mtime)) {
		return false;
	}

	return true;
}

/******************************************************************
 Force a "sticky" write time on an fsp. This will always be
 returned on all future write time queries and set on close.
******************************************************************/

bool set_sticky_write_time_fsp(struct files_struct *fsp, const struct timespec mtime)
{
	fsp->write_time_forced = true;
	TALLOC_FREE(fsp->update_write_time_event);

	return set_sticky_write_time_path(fsp->conn, fsp->fsp_name,
			fsp->file_id, mtime);
}

/******************************************************************
 Update a write time immediately, without the 2 second delay.
******************************************************************/

bool update_write_time(struct files_struct *fsp)
{
	if (!set_write_time(fsp->file_id, timespec_current())) {
		return false;
	}

	notify_fname(fsp->conn, NOTIFY_ACTION_MODIFIED,
			FILE_NOTIFY_CHANGE_LAST_WRITE, fsp->fsp_name);

	return true;
}
