# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package EBox::UsersAndGroups;

use strict;
use warnings;

use base qw(EBox::Module EBox::LdapModule);

use EBox::Global;
use EBox::Ldap;
use EBox::Gettext;
use EBox::Menu::Folder;
use EBox::Menu::Item;
use EBox::Sudo qw( :all );
use EBox::LdapUserImplementation;

use constant USERSDN	    => 'ou=Users';
use constant GROUPSDN       => 'ou=Groups';
use constant MINUID	    => 2000;
use constant MINGID	    => 2001;
use constant HOMEPATH       => '/nonexistent';
use constant MAXUSERLENGTH  => 24;
use constant MAXGROUPLENGTH => 24;
use constant MAXPWDLENGTH   => 15;
use constant DEFAULTGROUP   => '__USERS__';
 
sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'users',
					  domain => 'ebox-usersandgroups',
					  @_);

	$self->{ldap} = new EBox::Ldap();

	bless($self, $class);
	return $self;
}

sub _regenConfig 
{
	my $self = shift;
	
	my @array = ();
	my @acls = ();
	push (@array, 'dn'      => $self->{ldap}->dn);
	push (@array, 'rootdn'  => $self->{ldap}->rootDn);
	push (@array, 'rootpw'  => $self->{ldap}->rootPw);
	push (@array, 'schemas' => $self->allLDAPIncludes);
	push (@array, 'acls'    => $self->allLDAPAcls);


	$self->writeConfFile($self->{ldap}->slapdConfFile, 
	 		     "/usersandgroups/slapd.conf.mas", \@array);
}

sub rootCommands 
{
	my $self = shift;
	my @array = ();
	my $ldapconf = $self->{ldap}->slapdConfFile;

	push(@array, "/bin/mv " . EBox::Config::tmp ."* " . $ldapconf);
	push(@array, "/etc/init.d/slapd *");
	push(@array, "/bin/chmod * " . $ldapconf);
	push(@array, "/bin/chown * " . $ldapconf);

	return @array;
}

sub groupsDn
{
	my $self = shift;
	return GROUPSDN . "," . $self->{ldap}->dn;
}

sub usersDn 
{
	my $self = shift;
	return USERSDN . "," . $self->{ldap}->dn;
}

sub userExists($$) 
{
	my $self = shift;
	my $user = shift;

	my %attrs = (
			base => $self->usersDn,
			filter => "&(objectclass=*)(uid=$user)",
			scope => 'one'
		     );

	my $result = $self->{'ldap'}->search(\%attrs);

	return ($result->count > 0);
}

sub uidExists($$) 
{
	my $self = shift;
	my $uid = shift;

	my %attrs = (
			base => $self->usersDn,
			filter => "&(objectclass=*)(memberUid=$uid)",
			scope => 'one'
		     );

	my $result = $self->{'ldap'}->search(\%attrs);
	
	return ($result->count > 0);
}

sub lastUid($) 
{
	my $self = shift;
	
	my %args = (
			base => $self->usersDn,
			filter => '(objectclass=posixAccount)',
			scope => 'one', 
			attrs => ['uidNumber']
		   );

	my $result = $self->{ldap}->search(\%args);

	my @users = $result->sorted('uidNumber');

	my $uid = -1;
	foreach my $user (@users) {
		my $curruid = $user->get_value('uidNumber');
		if ( $curruid > $uid){
			$uid = $curruid;
		}
	}

	return ($uid < MINUID ?  MINUID : $uid);
}

sub _initUser($$) 
{
	my $self = shift;
	my $user = shift;
	
	# Tell modules depending on users and groups
	# a new new user is created
	my @mods = @{$self->_modsLdapUserBase()};
	
	foreach my $mod (@mods){
		$mod->_addUser($user);
	}
}



sub addUser($$) 
{
	my $self = shift;
	my $user = shift;

	if (length($user->{'user'}) > MAXUSERLENGTH) {
		throw EBox::Exceptions::External(
			__("Username must be at most " . MAXUSERLENGTH .
			   "characters long"));
	}
	unless (_checkName($user->{'user'})) {
		throw EBox::Exceptions::InvalidData(
					'data' => __('user name'),
					'value' => $user->{'user'});
	}

	 # Verify user exists
	if ($self->userExists($user->{'user'})) {
		throw EBox::Exceptions::DataExists('data' => __('user name'),
						   'value' => $user->{'user'});
	}

	my $uid = $self->lastUid + 1;
	my $gid = $self->groupGid(DEFAULTGROUP);
	
	$self->_checkPwdLength($user->{'password'});
	my %args = ( 
		    attr => [
			     'cn'	    => $user->{'user'},
			     'uid'	   => $user->{'user'},
			     'sn'	    => $user->{'fullname'},
			     'uidNumber'     => $uid,
			     'gidNumber'     => $gid,
			     'homeDirectory' => HOMEPATH ,
			     'userPassword'  => $user->{'password'},
			     'objectclass'   => ['inetOrgPerson','posixAccount']
			      ]
		   );

	my $dn = "uid=" . $user->{'user'} . "," . $self->usersDn;	
	my $r = $self->{'ldap'}->add($dn, \%args);
	

	$self->_changeAttribute($dn, 'description', $user->{'comment'});
	$self->_initUser($user->{'user'});
}

sub _modifyUserPwd($$$) 
{
	my $self = shift;
	my $user = shift;
	my $pwd  = shift;

	$self->_checkPwdLength($pwd);
	my $dn = "uid=" . $user . "," . $self->usersDn;	
	my $r = $self->{'ldap'}->modify($dn, { 
				replace => { 'userPassword' => $pwd }});
	
}

sub _updateUser($$) 
{
	my $self = shift;
	my $user = shift;
	
	# Tell modules depending on users and groups
	# a user  has been updated
	my @mods = @{$self->_modsLdapUserBase()};
	
	foreach my $mod (@mods){
		$mod->_modifyUser($user);
	}
}

sub modifyUser ($$$) 
{
	my $self =  shift;
	my $user =  shift;

	my $cn = $user->{'username'};
	my $dn = "uid=$cn," . $self->usersDn;
   	# Verify user  exists
	unless ($self->userExists($user->{'username'})) {
		throw EBox::Exceptions::DataNotFound('data'  => __('user name'),
						     'value' => $cn);
	}

	foreach my $field (keys %{$user}) {
		if ($field eq 'comment') {
			$self->_changeAttribute($dn, 'description', 
						$user->{'comment'});
		} elsif ($field eq 'fullname') {
			$self->_changeAttribute($dn, 'sn', $user->{'fullname'});
		} elsif ($field eq 'password') {
			$self->_modifyUserPwd($user->{'username'}, 
						$user->{'password'});
		}
	}
	
	$self->_updateUser($cn);
}

# Clean user stuff when deleting a user
sub _cleanUser($$) 
{
	my $self = shift;
	my $user = shift;

	my @mods = @{$self->_modsLdapUserBase()};
	
	# Tell modules depending on users and groups
	# an user is to be deleted 
	foreach my $mod (@mods){
		$mod->_delUser($user);
	}
	
	# Delete user from groups
	foreach my $group (@{$self->groupOfUsers($user)}) {
		$self->delUserFromGroup($user, $group);		
	}
}

sub delUser ($$) 
{
	my $self = shift;
	my $user = shift;

	# Verify user exists
	unless ($self->userExists($user)) {
		throw EBox::Exceptions::DataNotFound('data' => __('user name'),
						     'value' => $user);
	}

	$self->_cleanUser($user);	
	my $r = $self->{'ldap'}->delete("uid=" . $user . "," . $self->usersDn);
	
}

sub userInfo($$;$) 
{
	my $self = shift;
	my $user = shift;
	my $entry = shift;

	# Verify user  exists
	unless ($self->userExists($user)) {
		throw EBox::Exceptions::DataNotFound('data' => __('user name'),
						     'value' => $user);
	}
	
	# If $entry is undef we make a search to get the object, otherwise
	# we already have the entry
	unless ($entry) {
		my %args = (
			   base => $self->usersDn,
			   filter => "&(objectclass=*)(uid=$user)",
			   scope => 'one',
			   attrs => ['cn', 'description', 'userPassword', 'sn', 
				     'homeDirectory', 'uidNumber', 'gidNumber']
		   );

		my $result = $self->{ldap}->search(\%args);
		$entry = $result->entry(0);	
	}
	
	# Mandatory data
	my $userinfo = {
			username => $entry->get_value('cn'),
			fullname => $entry->get_value('sn'),
			password => $entry->get_value('userPassword'),
			homeDirectory => $entry->get_value('homeDirectory'),
			uid => $entry->get_value('uidNumber'),
			group => $entry->get_value('gidNumber'),
			};
     
	# Optional Data
	my $desc = $entry->get_value('description');
	if ($desc) {
		$userinfo->{'comment'} = $desc;
	} else {
		$userinfo->{'comment'} = ""; 
	}

	return $userinfo;

}

sub users($) 
{
	my $self = shift;
	
	my %args = (
			base => $self->usersDn,
			filter => 'objectclass=*',
			scope => 'one',
			attrs => ['uid', 'cn', 'sn', 'homeDirectory',  
				  'userPassword', 'uidNumber', 'gidNumber', 
				  'description']
		   );

	my $result = $self->{ldap}->search(\%args);
	
	my @users = ();
	foreach my $user ($result->sorted('uid'))
	{
		next if ($user->get_value('uidNumber') < MINUID);
		@users = (@users,  $self->userInfo($user->get_value('uid'),
						       $user))		
	}

	return @users;
}

sub groupExists($$) 
{
	my $self = shift;
	my $group = shift;

	my %attrs = (
		   	base => $self->groupsDn,
			filter => "&(objectclass=*)(cn=$group)",
			scope => 'one'
		     );

	my $result = $self->{'ldap'}->search(\%attrs);

	return ($result->count > 0);
}

sub gidExists($$) 
{
	my $self = shift;
	my $gid = shift;

	my %attrs = (
		   	base => $self->groupsDn,
			filter => "&(objectclass=*)(gidNumber=$gid)",
			scope => 'one'
		     );

	my $result = $self->{'ldap'}->search(\%attrs);

	return ($result->count > 0);
}

sub lastGid($) 
{
	my $self = shift;
	
	my %args = (
			base => $self->groupsDn,
			filter => '(objectclass=posixGroup)',
			scope => 'one', 
			attrs => ['gidNumber']
		   );

	my $result = $self->{ldap}->search(\%args);

	my @users = $result->sorted('gidNumber');

	my $gid = -1;
	foreach my $user (@users) {
		my $currgid = $user->get_value('gidNumber');
		if ( $currgid > $gid){
			$gid = $currgid;
		}
	}

	return ($gid < MINGID ?  MINGID : $gid);
}

sub addGroup($$) 
{
	my $self = shift;
	
	my $group = shift;
	my $comment = shift;

	if (length($group) > MAXGROUPLENGTH) {
		throw EBox::Exceptions::External(
			__("Groupname must be at most " . MAXGROUPLENGTH .
			   "characters long"));
	}
	
	if ($group eq DEFAULTGROUP) {
		throw EBox::Exceptions::External(
			__('The group name is not valid because it is used' .
			   ' internally'));
	}
	
	unless (_checkName($group)) {
		throw EBox::Exceptions::InvalidData(
				'data' => __('group name'),
				'value' => $group);
	}
 	# Verify group exists
	if ($self->groupExists($group)) {
		throw EBox::Exceptions::DataExists('data' => __('group name'),
						   'value' => $group);
	}
	#FIXME
	my $gid = $self->lastGid + 1;

	my %args = ( 
		    attr => [
			      'cn'	  => $group,
			      'gidNumber'   => $gid,
			      'objectclass' => ['posixGroup']
			    ]
		    );

	my $dn = "cn=" . $group ."," . $self->groupsDn;
	my $r = $self->{'ldap'}->add($dn, \%args); 
	
	
	$self->_changeAttribute($dn, 'description', $comment);

	my @mods = @{$self->_modsLdapUserBase()};
	foreach my $mod (@mods){
		$mod->_addGroup($group);
	}
}

sub modifyGroup ($$$) 
{
	my $self =  shift;
	my $groupdata =  shift;

	my $cn = $groupdata->{'groupname'};
	my $dn = "cn=$cn," . $self->groupsDn;
   	# Verify group  exists
	unless ($self->groupExists($cn)) {
		throw EBox::Exceptions::DataNotFound('data'  => __('user name'),
						     'value' => $cn);
	}

	$self->_changeAttribute($dn, 'description', $groupdata->{'comment'});
}

# Clean group stuff when deleting a user
sub _cleanGroup($$) 
{
	my $self = shift;
	my $group= shift;

	my @mods = @{$self->_modsLdapUserBase()};
	
	# Tell modules depending on users and groups
	# a group is to be deleted 
	foreach my $mod (@mods){
		$mod->_delGroup($group);
	}
}

sub delGroup($$) 
{
	my $self = shift;
	my $group = shift;

	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFoud('data' => __('group name'),
						    'value' => $group);
	}

	my $dn = "cn=" . $group . "," . $self->groupsDn;
	my $result = $self->{'ldap'}->delete($dn);

	$self->_cleanGroup($group);
}

sub groupInfo($$) 
{
	my $self = shift;
	my $group = shift;

	# Verify user don't exists
	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFound('data' => __('user name'),
						     'value' => $group);
	}

	my %args = (
			base => $self->groupsDn,
			filter => "&(objectclass=*)(cn=$group)",
			scope => 'one',
			attrs => ['cn', 'description']
		   );

	my $result = $self->{ldap}->search(\%args);

	my $entry = $result->entry(0);
	# Mandatory data
	my $groupinfo = {
			 groupname => $entry->get_value('cn'),
			};
	
	
	my $desc = $entry->get_value('description');
	if ($desc) {
		$groupinfo->{'comment'} = $desc;
	} else {
		$groupinfo->{'comment'} = ""; 
	}

	return $groupinfo;

}

sub groups 
{
	my $self = shift;
	
	my %args = (
		      base => $self->groupsDn,
		      filter => '(objectclass=*)',
		      scope => 'one', 
		      attrs => ['cn', 'gidNumber', 'description']
		   );

	my $result = $self->{ldap}->search(\%args);

	my @groups = ();
	foreach ($result->sorted('cn'))
	{
		next if ($_->get_value('gidNumber') < MINGID);

		my $info = {
				'account' => $_->get_value('cn'),
				'gid' => $_->get_value('gidNumber'),
			    };

		my $desc = $_->get_value('description');
		if ($desc) {
			$info->{'desc'} = $desc;
		}

		@groups = (@groups, $info);
	}

	return @groups;
}

sub addUserToGroup($$$) 
{
	my $self = shift;

	my $user = shift;
	my $group = shift;

	unless ($self->userExists($user)) {
		throw EBox::Exceptions::DataNotFound('data' => __('user name'),
						     'value' => $user);
	}

	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFound('data' => __('group name'),
						     'value' => $group);
	}

	my $dn = "cn=" . $group . "," . $self->groupsDn;

	my %attrs = ( add => { memberUid => $user } );
 	$self->{'ldap'}->modify($dn, \%attrs);
}

sub delUserFromGroup($$$) 
{
	my $self = shift;

	my $user = shift;
	my $group = shift;

	unless ($self->userExists($user)) {
		throw EBox::Exceptions::DataNotFound('data' => __('user name'),
						     'value' => $user);
	}

	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFoud('data' => __('group name'),
						    'value' => $group);
	}

	my $dn = "cn=" . $group . "," . $self->groupsDn;
	my %attrs = ( delete => {  memberUid => $user  } );
	$self->{'ldap'}->modify($dn, \%attrs);
}


sub groupOfUsers($$) 
{
	my $self = shift;
	my $user = shift;

	unless ($self->userExists($user)) {
		throw EBox::Exceptions::DataNotFound('data' => __('user name'),
						     'value' => $user);
	}

	my %attrs = (
		       base => $self->groupsDn,
		       filter => "&(objectclass=*)(memberUid=$user)",
		       scope => 'one',
		       attrs => ['cn']
		    );
	
	my $result = $self->{'ldap'}->search(\%attrs);

	my @groups;
	foreach my $entry ($result->entries){
		push @groups, $entry->get_value('cn');
	}
	
	return \@groups;
}

sub  usersInGroup ($$) 
{
	my $self = shift;
	my $group= shift;

	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFound('data' => __('group name'),
						     'value' => $group);
	}

	my %attrs = (
		       base => $self->groupsDn,
		       filter => "&(objectclass=*)(cn=$group)",
		       scope => 'one',
		       attrs => ['memberUid']
		    );
	
	my $result = $self->{'ldap'}->search(\%attrs);

	my @users;
	foreach my $res ($result->sorted('memberUid')){
		push @users, $res->get_value('memberUid');
	}
	
	return \@users;

}

sub usersNotInGroup($$)
{
	my $self  = shift;
	my $groupname = shift;
	
	my $grpusers = $self->usersInGroup($groupname);
	my @allusers = $self->users();

	my @users;
	foreach my $user (@allusers){
		my $uid = $user->{username};
		unless (grep (/^$uid$/, @{$grpusers})){
			push @users, $uid;
		}
	}

	return @users;
}



sub gidGroup($$) 
{
	my $self = shift;
	my $gid  = shift;

	my %attrs = (
		   	base => $self->groupsDn,
			filter => "&(objectclass=*)(gidNumber=$gid)",
			scope => 'one',
			attr => ['cn']
		     );

	my $result = $self->{'ldap'}->search(\%attrs);
	
	if ($result->count == 0){
		  throw EBox::Exceptions::DataNotFound(
			'data' => "Gid", 'value' => $gid);
	}	

	return $result->entry(0)->get_value('cn');
}	

sub groupGid($$) 
{
	my $self = shift;
	my $group  = shift;

	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFound('data' => __('group name'),
						     'value' => $group);
	}

	my %attrs = (
		   	base => $self->groupsDn,
			filter => "&(objectclass=*)(cn=$group)",
			scope => 'one',
			attr => ['cn']
		     );

	my $result = $self->{'ldap'}->search(\%attrs);
	
	return $result->entry(0)->get_value('gidNumber');
}

sub _groupIsEmpty($$) 
{
	my $self = shift;
	my $group = shift;
	
	my @users = @{$self->usersInGroup($group)};

	return @users ? undef : 1;
}

sub _changeAttribute 
{
	my $self = shift;
	my $dn   = shift;
	my $attr = shift;
	my $value = shift;

	unless ($value and length($value) > 0){
		$value = undef;
	}
	my %args = (
		      base => $dn,
		      filter => 'objectclass=*',
		      scope =>  'base'
		   );

	my $result = $self->{ldap}->search(\%args);

	my $entry = $result->pop_entry();
	my $oldvalue = $entry->get_value($attr);

	# There is no value 
	return if ( (not $value) and (not $oldvalue));  
	# There is no change
	return if (($oldvalue and $value) and $oldvalue eq $value); 
	
	if (($oldvalue and $value) and $value ne $oldvalue) {
		$entry->replace($attr => $value);
	} elsif ((not $value) and $oldvalue) {
		$entry->delete($attr);
	} elsif (($value) and (not $oldvalue)) {
		$entry->add($attr => $value);
	}
	
	$entry->update($self->{ldap}->ldapCon);
	
}



sub _checkPwdLength($$) 
{
	my $self = shift;
	my $pwd  = shift;
	
	if (length($pwd) > MAXPWDLENGTH) {
		throw EBox::Exceptions::External(
			__("Password must be at most " . MAXPWDLENGTH .
			   "characters long"));
	}
}


sub _checkName
{
	my $name = shift;
	($name =~ /[^\w\s]/) and return undef;
	return 1;
}

# Returns modules implementing LDAP user base interface
sub _modsLdapUserBase($) 
{
	my $self = shift;

	my $global = EBox::Global->modInstance('global');
	my @names = @{$global->modNames};
	
	my @modules;
	foreach my $name (@names) {
		my $mod = EBox::Global->modInstance($name);
		if ($mod->isa('EBox::LdapModule')) {
			push (@modules, $mod->_ldapModImplementation);
		}
	}
	
	return \@modules;
}

sub allUserAddOns($$) 
{
	my $self = shift;
	my $username = shift;

	my $global = EBox::Global->modInstance('global');
	my @names = @{$global->modNames};
	
	my @modsFunc = @{$self->_modsLdapUserBase()};
	my @components;
	foreach my $mod (@modsFunc) {
		my $comp = $mod->_userAddOns($username);
		if ($comp) {
			push (@components, $comp);
		}
	}
	
	return \@components;
}


sub allGroupAddOns($$) 
{
	my $self = shift;
	my $groupname = shift;

	my $global = EBox::Global->modInstance('global');
	my @names = @{$global->modNames};
	
	my @modsFunc = @{$self->_modsLdapUserBase()};
	my @components;
	foreach my $mod (@modsFunc) {
		my $comp = $mod->_groupAddOns($groupname);
	 	push (@components, $comp) if ($comp); 
	}
	
	return \@components;
}

sub allLDAPIncludes 
{
	my $self = shift;
	
	my @modsFunc = @{$self->_modsLdapUserBase()};
	my @includes;
	foreach my $mod (@modsFunc) {
		foreach my $path (@{$mod->_includeLDAPSchemas}) {
			push (@includes,  $path) if ($path);
		}
	}

	return \@includes;
}

sub allLDAPAcls 
{
	my $self = shift;

	my @modsFunc = @{$self->_modsLdapUserBase()};
	my @allAcls;
	foreach my $mod (@modsFunc) {
		foreach my $acl (@{$mod->_includeLDAPAcls}) {
			push (@allAcls,  $acl) if ($acl);
		}
	}

	return \@allAcls;
}

sub allWarnings($$$) 
{
	my $self = shift;
	my $object = shift;
	my $name = shift;
	
	my @modsFunc = @{$self->_modsLdapUserBase()};
	my @allWarns;
	foreach my $mod (@modsFunc) {
		my $warn = undef;
		if ($object eq 'user') {
			$warn = $mod->_delUserWarning($name);
		} else {
			$warn = $mod->_delGroupWarning($name);
		}
		push (@allWarns, $warn) if ($warn);
	}

	return \@allWarns;
}

sub menu
{
        my ($self, $root) = @_;
        $root->add(new EBox::Menu::Item('url' => 'UsersAndGroups/Users',
                                        'text' => __('Users')));
        $root->add(new EBox::Menu::Item('url' => 'UsersAndGroups/Groups',
                                        'text' => __('Groups')));
}

# LdapModule implmentation 
sub _ldapModImplementation 
{
	my $self;
	
	return new EBox::LdapUserImplementation();
}

1;
