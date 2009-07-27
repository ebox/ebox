# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
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

use base qw(EBox::Module::Service
            EBox::LdapModule
            EBox::Model::ModelProvider
            EBox::UserCorner::Provider
          );

use EBox::Global;
use EBox::Ldap;
use EBox::Gettext;
use EBox::Menu::Folder;
use EBox::Menu::Item;
use EBox::Sudo qw( :all );
use EBox::FileSystem;
use EBox::LdapUserImplementation;
use EBox::Config;
use EBox::UsersAndGroups::Passwords;

use Digest::SHA1;
use Digest::MD5;
use Crypt::SmbHash;

use Error qw(:try);
use File::Copy;
use Perl6::Junction qw(any);

use constant USERSDN        => 'ou=Users';
use constant GROUPSDN       => 'ou=Groups';
use constant SYSMINUID      => 1900;
use constant SYSMINGID      => 1900;
use constant MINUID         => 2000;
use constant MINGID         => 2000;
use constant HOMEPATH       => '/nonexistent';
use constant MAXUSERLENGTH  => 24;
use constant MAXGROUPLENGTH => 24;
use constant MAXPWDLENGTH   => 512;
use constant DEFAULTGROUP   => '__USERS__';

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'users',
                                      printableName => __('users and groups'),
                                      domain => 'ebox-usersandgroups',
                                      @_);

    $self->{ldap} = EBox::Ldap->instance();

    bless($self, $class);
    return $self;
}

# Method: actions
#
#       Override EBox::Module::Service::actions
#
sub actions
{
    return [
            {
             'action' => __('Your current openLDAP database will be replaced ' .
                            'and backed up in /var/backups/slapd'),
                'reason' => __('eBox will initialize openLDAP to store its database. ' .
                               'It will also overwrite your current configuration'),
             'module' => 'users'
        }
           ];
}

# Method: usedFiles
#
#       Override EBox::Module::Service::files
#
sub usedFiles
{
    return [
            {
             'file' => '/etc/default/slapd',
             'reason' => __('To make openLDAP listen on TCP and Unix sockets'),
             'module' => 'users'
            },
        {
         'file' => '/etc/ldap/slapd.conf',
         'reason' => __('To configure the openLDAP database with dc ' .
                        ' entry, rootpw, rootdn, schemas and ACLs used by '.
                        ' the LDAP based eBox modules'),
         'module' => 'users'
        }
           ];
}

# Method: enableActions
#
#       Override EBox::Module::Service::enableActions
#
sub enableActions
{
    command(EBox::Config::share() . '/ebox-usersandgroups/ebox-init-ldap init');
}

# Method: writeLDAPConf
#
#  Public method to generate slapd.conf
#
sub writeLDAPConf
{
    my ($self) =  @_;
    $self->_setConf();
}

# Method: _setConf
#
#       Overrides base method. It regenerates the ldap service configuration
#
sub _setConf
{
    my ($self) = @_;

    my @array = ();

    push (@array, 'dn'      => $self->{ldap}->dn);
    push (@array, 'rootdn'  => $self->{ldap}->rootDn);
    push (@array, 'rootpw'  => $self->{ldap}->rootPw);
    push (@array, 'schemas' => $self->allLDAPIncludes);
    push (@array, 'acls'    => $self->allLDAPAcls);

    $self->writeConfFile($self->{ldap}->slapdConfFile,
                         "/usersandgroups/slapd.conf.mas", \@array);
}


# Method: modelClasses
#
#       Override <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
        'EBox::UsersAndGroups::Model::Users',
        'EBox::UsersAndGroups::Model::Groups',
        'EBox::UsersAndGroups::Model::Password',
    ];
}

# Method: groupsDn
#
#       Returns the dn where the groups are stored in the ldap directory
#
# Returns:
#
#       string - dn
#
sub groupsDn
{
    my ($self) = @_;
    return GROUPSDN . "," . $self->{ldap}->dn;
}


# Method: groupDn
#
#    Returns the dn for a given group. The group don't have to existst
#
#   Parameters:
#       group
#
#  Returns:
#     dn for the group
sub groupDn
{
    my ($self, $group) = @_;
    $group or throw EBox::Exceptions::MissingArgument('group');

    my $dn = "cn=$group," .  $self->groupsDn;
    return $dn;
}

# Method: usersDn
#
#       Returns the dn where the users are stored in the ldap directory
#
# Returns:
#
#       string - dn
#
sub usersDn
{
    my ($self) = @_;
    return USERSDN . "," . $self->{ldap}->dn;
}

# Method: userDn
#
#    Returns the dn for a given user. The user don't have to existst
#
#   Parameters:
#       user
#
#  Returns:
#     dn for the user
sub userDn
{
    my ($self, $user) = @_;
    $user or throw EBox::Exceptions::MissingArgument('user');

    my $dn = "uid=$user," .  $self->usersDn;
    return $dn;
}



# Method: userExists
#
#       Checks if a given user exists
#
# Parameters:
#
#       user - user name
#
# Returns:
#
#       boolean - true if it exists, otherwise false
#
sub userExists # (user)
{
    my ($self, $user) = @_;

    my %attrs = (
                 base => $self->usersDn,
                 filter => "&(objectclass=*)(uid=$user)",
                 scope => 'one'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    return ($result->count > 0);
}


# Method: uidExists
#
#       Checks if a given uid exists
#
# Parameters:
#
#       uid - uid number to check
#
# Returns:
#
#       boolean - true if it exists, otherwise false
#
sub uidExists # (uid)
{
    my ($self, $uid) = @_;

    my %attrs = (
                 base => $self->usersDn,
                 filter => "&(objectclass=*)(uidNumber=$uid)",
                 scope => 'one'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    return ($result->count > 0);
}

# Method: lastUid
#
#       Returns the last uid used.
#
# Parameters:
#
#       system - boolan: if true, it returns the last uid for system users,
#       otherwise the last uid for normal users
#
# Returns:
#
#       string - last uid
#
sub lastUid # (system)
{
    my ($self, $system) = @_;

    my %args = (
                base =>  $self->{ldap}->dn(),
                filter => '(objectclass=posixAccount)',
                scope => 'sub',
                attrs => ['uidNumber']
               );

    my $result = $self->{ldap}->search(\%args);

    my @users = $result->sorted('uidNumber');

    my $uid = -1;
    foreach my $user (@users) {
        my $curruid = $user->get_value('uidNumber');
        if ($system) {
            last if ($curruid >= MINUID);
        } else {
            next if ($curruid < MINUID);
        }
        if ( $curruid > $uid){
            $uid = $curruid;
        }
    }

    if ($system) {
        return ($uid < SYSMINUID ?  SYSMINUID : $uid);
    } else {
        return ($uid < MINUID ?  MINUID : $uid);
    }
}

sub _initUser
{
    my ($self, $user, $password) = @_;

    # Tell modules depending on users and groups
    # a new new user is created
        my @mods = @{$self->_modsLdapUserBase()};

    foreach my $mod (@mods){
        $mod->_addUser($user, $password);
    }
}


# Method: addUser
#
#       Adds a user
#
# Parameters:
#
#       user - hash ref containing: 'user'(user name), 'fullname', 'password',
#       'givenname', 'surname' and comment
#       system - boolean: if true it adds the user as system user, otherwise as
#       normal user
#       uidNumber - user UID numberer (optional and named)
#       additionalPasswords -list with additional passwords (optional)
sub addUser # (user, system)
{
    my ($self, $user, $system, %params) = @_;

    if (length($user->{'user'}) > MAXUSERLENGTH) {
        throw EBox::Exceptions::External(
                                         __x("Username must not be longer than {maxuserlength} characters",
                           maxuserlength => MAXUSERLENGTH));
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

    my $uid = exists $params{uidNumber} ?
        $params{uidNumber} :
            $self->_newUserUidNumber($system);
    $self->_checkUid($uid, $system);

    my $gid = $self->groupGid(DEFAULTGROUP);

    my $passwd = $user->{'password'};
    if (not isHashed($passwd)) {
        $passwd =  defaultPasswordHash($passwd);
    }

    my @additionalPasswords = ();
    if (exists $params{additionalPasswords}) {
        @additionalPasswords = @{ $params{additionalPasswords} }
    } else {
        # build addtional passworfs using not-hashed pasword
        isHashed($user->{password}) and
            throw EBox::Exceptions::Internal(
'The supplied user password is already hashed, you must supply an additional password list'
)          ;

        @additionalPasswords = @{EBox::UsersAndGroups::Passwords::additionalPasswords(
            $user->{'user'},
            $user->{'password'}
           );
        }
    }

    # If fullname is not specified we build it with
    # givenname and surname
    unless (defined $user->{'fullname'}) {
        $user->{'fullname'} = '';
        if ($user->{'givenname'}) {
            $user->{'fullname'} = $user->{'givenname'} . ' ';
        }
        $user->{'fullname'} .= $user->{'surname'};
    }

    $self->_checkPwdLength($user->{'password'});
    my @attr =  (
        'cn'            => $user->{'fullname'},
        'uid'           => $user->{'user'},
        'sn'            => $user->{'surname'},
        'uidNumber'     => $uid,
        'gidNumber'     => $gid,
        'homeDirectory' => HOMEPATH,
        'userPassword'  => $passwd,
        'objectclass'   => ['inetOrgPerson', 'posixAccount', 'passwordHolder'],
        @additionalPasswords
    );



    my %args = ( attr => \@attr );

    my $dn = "uid=" . $user->{'user'} . "," . $self->usersDn;
    my $r = $self->{'ldap'}->add($dn, \%args);


    $self->_changeAttribute($dn, 'givenName', $user->{'givenname'});
    $self->_changeAttribute($dn, 'description', $user->{'comment'});
    unless ($system) {
        $self->_initUser($user->{'user'}, $user->{'password'});
    }
}

sub _newUserUidNumber
{
    my ($self, $systemUser) = @_;

    my $uid;
    if ($systemUser) {
        $uid = $self->lastUid(1) + 1;
        if ($uid == MINUID) {
            throw EBox::Exceptions::Internal(
                __('Maximum number of system users reached'));
        }
    } else {
        $uid = $self->lastUid + 1;
    }

    return $uid;
}


sub _checkUid
{
    my ($self, $uid, $system) = @_;

    if ($uid < MINUID) {
        if (not $system) {
            throw EBox::Exceptions::External(
                                              __x('Incorrect UID {uid} for a user . UID must be equal or greater than {min}',
                                                  uid => $uid,
                                                  min => MINUID,
                                                 )
                                             );
        }

    }
    else {
        if ($system) {
            throw EBox::Exceptions::External(
                                              __x('Incorrect UID {uid} for a system user . UID must be lesser than {max}',
                                                  uid => $uid,
                                                  max => MINUID,
                                                 )
                                             );

        }
    }

}

sub _modifyUserPwd
{
    my ($self, $user, $passwd) = @_;

    $self->_checkPwdLength($passwd);
    my $hash = defaultPasswordHash($passwd);
    my $dn = "uid=" . $user . "," . $self->usersDn;

    my %args = (
                base => $self->usersDn,
                filter => "&(objectclass=*)(uid=$user)",
                scope => 'one',
                attrs => ['*'],
               );

    my $result = $self->{ldap}->search(\%args);
    my $entry = $result->entry(0);

    #remove old passwords
    my $delattrs = [];
    foreach my $attr ($entry->attributes) {
        if ($attr =~ m/^ebox(.*)Password$/) {
            push(@{$delattrs}, $attr);
        }
    }
    $self->{ldap}->modify($dn, { 'delete' => $delattrs } );

    #add new passwords
    my %attrs = (
        changes => [
            replace => [
                'userPassword' => $hash,
                @{EBox::UsersAndGroups::Passwords::additionalPasswords($user, $passwd)}
            ]
        ]
    );
    if(! $self->{ldap}->isObjectClass($dn, 'passwordHolder')) {
        push(@{$attrs{'changes'}}, 'add', ['objectclass' => 'passwordHolder']);
    }
    $self->{ldap}->modify($dn, \%attrs);
}

sub _updateUser
{
    my ($self, $user, $password) = @_;

    # Tell modules depending on users and groups
    # a user  has been updated
    my @mods = @{$self->_modsLdapUserBase()};

    foreach my $mod (@mods){
        $mod->_modifyUser($user, $password);
    }
}

# Method: modifyUser
#
#       Modifies  user's attributes
#
# Parameters:
#
#       user - hash ref containing: 'user' (user name), 'givenname', 'surname',
#       'password', and comment. The only mandatory parameter is 'user' the
#       other attribute parameters would be ignored if they are missing.
#
sub modifyUser # (\%user)
{
    my ($self, $user) = @_;

    my $uid = $user->{'username'};
    my $dn = $self->userDn($uid);
    # Verify user exists
    unless ($self->userExists($user->{'username'})) {
        throw EBox::Exceptions::DataNotFound('data'  => __('user name'),
                                             'value' => $uid);
    }

    foreach my $field (keys %{$user}) {
        if ($field eq 'comment') {
            $self->_changeAttribute($dn, 'description',
                                    $user->{'comment'});
        } elsif ($field eq 'givenname') {
            $self->_changeAttribute($dn, 'givenName', $user->{'givenname'});
        } elsif ($field eq 'surname') {
            $self->_changeAttribute($dn, 'sn', $user->{'surname'});
        } elsif ($field eq 'fullname') {
            $self->_changeAttribute($dn, 'cn', $user->{'fullname'});
        } elsif ($field eq 'password') {
            my $pass = $user->{'password'};
            $self->_modifyUserPwd($user->{'username'}, $pass);
        }
    }
    $self->_updateUser($uid, $user->{'password'});
}

# Clean user stuff when deleting a user
sub _cleanUser
{
    my ($self, $user) = @_;

    my @mods = @{$self->_modsLdapUserBase()};

    # Tell modules depending on users and groups
    # an user is to be deleted
    foreach my $mod (@mods){
        $mod->_delUser($user);
    }

    # Delete user from groups
    foreach my $group (@{$self->groupsOfUser($user)}) {
                $self->delUserFromGroup($user, $group);
            }
}

# Method: delUser
#
#       Removes a given user
#
# Parameters:
#
#       user - user name to be deleted
#
sub delUser # (user)
{
    my ($self, $user) = @_;

    # Verify user exists
    unless ($self->userExists($user)) {
        throw EBox::Exceptions::DataNotFound('data' => __('user name'),
                                             'value' => $user);
    }

    $self->_cleanUser($user);
    my $r = $self->{'ldap'}->delete("uid=" . $user . "," . $self->usersDn);

}

# Method: userInfo
#
#       Returns a hash ref containing the inforamtion for a given user
#
# Parameters:
#
#       user - user name to gather information
#       entry - *optional* ldap entry for the user
#
# Returns:
#
#       hash ref - holding the keys: 'username', 'givenname', 'surname', 'fullname'
#      password', 'homeDirectory', 'uid' and 'group'
#
sub userInfo # (user, entry)
{
    my ($self, $user, $entry) = @_;

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
                    attrs => ['*'],
                   );

        my $result = $self->{ldap}->search(\%args);
        $entry = $result->entry(0);
    }

    # Mandatory data
    my $userinfo = {
                    username => $entry->get_value('uid'),
                    fullname => $entry->get_value('cn'),
                    surname => $entry->get_value('sn'),
                    password => $entry->get_value('userPassword'),
                    homeDirectory => $entry->get_value('homeDirectory'),
                    uid => $entry->get_value('uidNumber'),
                    group => $entry->get_value('gidNumber'),
                    extra_passwords => {}
                   };

    foreach my $attr ($entry->attributes) {
        if ($attr =~ m/^ebox(.*)Password$/) {
            my $format = lc($1);
            $userinfo->{extra_passwords}->{$format} = $entry->get_value($attr);
        }
    }

    # Optional Data
    my $givenName = $entry->get_value('givenName');
    if ($givenName) {
        $userinfo->{'givenname'} = $givenName;
    } else {
        $userinfo->{'givenname'} = '';
    }
    my $desc = $entry->get_value('description');
    if ($desc) {
        $userinfo->{'comment'} = $desc;
    } else {
        $userinfo->{'comment'} = '';
    }

    return $userinfo;
}

# Method: uidList
#
#       Returns an ordered array containing all uid
#
# Returns:
#
#       array - holding the uid
#
sub uidList
{
    my ($self, $system) = @_;

    my %args = (
                base => $self->usersDn,
                filter => 'objectclass=*',
                scope => 'one',
                attrs => ['uid', 'uidNumber']
               );

    my $result = $self->{ldap}->search(\%args);

    my @users = ();
    foreach my $user ($result->sorted('uid'))
        {
            if (not $system) {
                next if ($user->get_value('uidNumber') < MINUID);
            }
            push (@users, $user->get_value('uid'));
        }

    return \@users;
}

# Method: users
#
#       Returns an array containing all the users (not system users)
#
# Parameters:
#       system - show system groups (default: false)
#
# Returns:
#
#       array - holding the users
#
sub users
{
    my ($self, $system) = @_;

    my %args = (
                base => $self->usersDn,
                filter => 'objectclass=*',
                scope => 'one',
                attrs => ['uid', 'cn', 'givenName', 'sn', 'homeDirectory',
                          'userPassword', 'uidNumber', 'gidNumber',
                          'description']
               );

    my $result = $self->{ldap}->search(\%args);

    my @users = ();
    foreach my $user ($result->sorted('uid'))
        {
            if (not $system) {
                next if ($user->get_value('uidNumber') < MINUID);
            }

            @users = (@users,  $self->userInfo($user->get_value('uid'),
                                               $user))
        }

    return @users;
}

# Method: usersList
#
#       Returns an array containing all the users (not system users)
#
# Returns:
#
#       array ref - containing hash refs with the following keys
#
#            user => user name
#            uid => uid number
#
sub usersList
{
    my ($self) = @_;

    my %args = (
                base => $self->usersDn,
                filter => 'objectclass=*',
                scope => 'one',
                attrs => ['uid', 'uidNumber']
               );

    my $result = $self->{ldap}->search(\%args);

    my @users = ();
    foreach my $user ($result->sorted('uid'))
        {
            next if ($user->get_value('uidNumber') < MINUID);
            push (@users,  { user => $user->get_value('uid'),
                    uid => $user->get_value('uidNumber') });
        }

    return \@users;
}


# Method: groupExists
#
#       Checks if a given group name exists
#
# Parameters:
#
#       group - group name
#
# Returns:
#
#       boolean - true if it exists, otherwise false
#
sub groupExists # (group)
{
    my ($self, $group) = @_;

    my %attrs = (
                 base => $self->groupsDn,
                 filter => "&(objectclass=*)(cn=$group)",
                 scope => 'one'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    return ($result->count > 0);
}

# Method: gidExists
#
#       Checks if a given gid number exists
#
# Parameters:
#
#       gid - gid number
#
# Returns:
#
#       boolean - true if it exists, otherwise false
#
sub gidExists
{
    my ($self, $gid) = @_;

    my %attrs = (
                 base => $self->groupsDn,
                 filter => "&(objectclass=*)(gidNumber=$gid)",
                 scope => 'one'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    return ($result->count > 0);
}

# Method: lastGid
#
#       Returns the last gid used.
#
# Parameters:
#
#       system - boolan: if true, it returns the last gid for system users,
#       otherwise the last gid for normal users
#
# Returns:
#
#       string - last gid
#
sub lastGid # (gid)
{
    my ($self, $system) = @_;

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
        if ($system) {
                        last if ($currgid > MINGID);
                    } else {
                        next if ($currgid < MINGID);
                    }

        if ( $currgid > $gid){
            $gid = $currgid;
        }
    }

    if ($system) {
        return ($gid < SYSMINUID ?  SYSMINUID : $gid);
    } else {
        return ($gid < MINUID ?  MINUID : $gid);
    }

}

# Method: addGroup
#
#       Adds a new group
#
# Parameters:
#
#       group - group name
#       comment - comment's group
#       system - boolan: if true it adds the group as system group,
#       otherwise as normal group
#
sub addGroup # (group, comment, system)
{
    my ($self, $group, $comment, $system, %params) = @_;

    if (length($group) > MAXGROUPLENGTH) {
        throw EBox::Exceptions::External(
                        __x("Groupname must not be longer than {maxGroupLength} characters",
                            maxGroupLength => MAXGROUPLENGTH));
    }

    if (($group eq DEFAULTGROUP) and (not $system)) {
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
    my $gid = exists $params{gidNumber} ?
        $params{gidNumber} :
            $self->_gidForNewGroup($system);

    $self->_checkGid($gid, $system);

    my %args = (
                attr => [
                         'cn'        => $group,
                         'gidNumber'   => $gid,
                         'objectclass' => ['posixGroup']
                            ]
               );

    my $dn = "cn=" . $group ."," . $self->groupsDn;
    my $r = $self->{'ldap'}->add($dn, \%args);


    $self->_changeAttribute($dn, 'description', $comment);

    unless ($system) {
        my @mods = @{$self->_modsLdapUserBase()};
        foreach my $mod (@mods){
            $mod->_addGroup($group);
        }
    }
}


sub _gidForNewGroup
{
    my ($self, $system) = @_;

    my $gid;
    if ($system) {
        $gid = $self->lastGid(1) + 1;
        if ($gid == MINGID) {
            throw EBox::Exceptions::Internal(
                                __('Maximum number of system users reached'));
        }
    } else {
        $gid = $self->lastGid + 1;
    }

    return $gid;
}


sub _checkGid
{
    my ($self, $gid, $system) = @_;

    if ($gid < MINGID) {
        if (not $system) {
            throw EBox::Exceptions::External(
                                              __x('Incorrect GID {gid} for a group . GID must be equal or greater than {min}',
                                                  gid => $gid,
                                                  min => MINGID,
                                                 )
                                             );
        }
    }
    else {
        if ($system) {
            throw EBox::Exceptions::External(
                                              __x('Incorrect GID {gid} for a system group . GID must be lesser than {max}',
                                                  gid => $gid,
                                                  max => MINGID,
                                                 )
                                             );

        }
    }

}




sub _updateGroup
{
    my ($self, $group) = @_;

    # Tell modules depending on groups and groups
    # a group  has been updated
    my @mods = @{$self->_modsLdapUserBase()};

    foreach my $mod (@mods){
        $mod->_modifyGroup($group);
    }
}

# Method: modifyGroup
#
#       Modifies a group
#
# Parameters:
#
#       hash ref - holding the keys 'groupname' and 'comment'. At the moment
#       comment is the only modifiable attribute
#
sub modifyGroup # (\%groupdata))
{
    my ($self, $groupdata) = @_;

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
sub _cleanGroup
{
    my ($self, $group) = @_;

    my @mods = @{$self->_modsLdapUserBase()};

    # Tell modules depending on users and groups
    # a group is to be deleted
    foreach my $mod (@mods){
        $mod->_delGroup($group);
    }
}

# Method: delGroup
#
#       Removes a given group
#
# Parameters:
#
#       group - group name to be deleted
#
sub delGroup # (group)
{
    my ($self, $group) = @_;

    unless ($self->groupExists($group)) {
        throw EBox::Exceptions::DataNotFoud('data' => __('group name'),
                                            'value' => $group);
    }

        $self->_cleanGroup($group);
        my $dn = "cn=" . $group . "," . $self->groupsDn;
        my $result = $self->{'ldap'}->delete($dn);

}

# Method: groupInfo
#
#       Returns a hash ref containing the inforamtion for a given group
#
# Parameters:
#
#       group - group name to gather information
#       entry - *optional* ldap entry for the group
#
# Returns:
#
#       hash ref - holding the keys: 'groupname' and 'description'
sub groupInfo # (group)
{
    my ($self, $group) = @_;

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

# Method: groups
#
#       Returns an array containing all the groups
#
#   Parameters:
#       system - show system groups (default: false)
#
# Returns:
#
#       array - holding the groups
#
# Warning:
#
#   the group hashes are NOT the sames that we get from groupInfo, the keys are:
#     account(group name), desc (description) and gid
sub groups
{
    my ($self, $system) = @_;
    defined $system or $system = 0;

    my %args = (
                base => $self->groupsDn,
                filter => '(objectclass=*)',
                scope => 'one',
                attrs => ['cn', 'gidNumber', 'description']
               );

    my $result = $self->{ldap}->search(\%args);

    my @groups = ();
    foreach ($result->sorted('cn')) {
        if (not $system) {
            next if ($_->get_value('gidNumber') < MINGID);
        }


        my $info = {
                    'account' => $_->get_value('cn'),
                    'gid' => $_->get_value('gidNumber'),
                   };

        my $desc = $_->get_value('description');
        if ($desc) {
            $info->{'desc'} = $desc;
        }

        push @groups, $info;
    }

    return @groups;
}

# Method: addUserToGroup
#
#       Adds a user to a given group
#
# Parameters:
#
#       user - user name to add to the group
#       group - group name
#
# Exceptions:
#
#       DataNorFound - If user or group don't exist
sub addUserToGroup # (user, group)
{
    my ($self, $user, $group) = @_;

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

    $self->_updateGroup($group);
}

# Method: delUserFromGroup
#
#       Removes a user from a group
#
# Parameters:
#
#       user - user name to remove  from the group
#       group - group name
#
# Exceptions:
#
#       DataNorFound - If user or group don't exist
sub delUserFromGroup # (user, group)
{
    my ($self, $user, $group) = @_;

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

    $self->_updateGroup($group);
}

# Method: groupsOfUser
#
#       Given a user it returns all the groups which the user belongs to
#
# Parameters:
#
#       user   - user name
#       system - show system groups (default: false) *optional*
#
# Returns:
#
#       array ref - holding the groups
#
# Exceptions:
#
#       DataNotFound - If user does not exist
#
sub groupsOfUser # (user, system?)
{
    my ($self, $user, $system) = @_;
    defined $system or $system = 0;

    return $self->_ldapSearchUserGroups($user, $system, 0);
}

# Method: groupsNotOfUser
#
#       Given a user it returns all the groups which the user doesn't belong to
#
# Parameters:
#
#       user   - user name
#       system - show system groups (default: false) *optional*
#
# Returns:
#
#       array ref - holding the groups
#
# Exceptions:
#
#       DataNotFound - If user does not  exist
#
sub groupsNotOfUser # (user, system?)
{
    my ($self, $user, $system) = @_;
    defined $system or $system = 0;

    return $self->_ldapSearchUserGroups($user, $system, 1);
}

sub _ldapSearchUserGroups # (user, system, inverse)
{
    my ($self, $user, $system, $inverse) = @_;

    unless ($self->userExists($user)) {
        throw EBox::Exceptions::DataNotFound('data' => __('user name'),
                                             'value' => $user);
    }

    my $filter = '&(objectClass=*)';
    if ($inverse) {
        $filter .= "(!(memberUid=$user))"
    } else {
        $filter .= "(memberUid=$user)";
    }

    my %attrs = (
                 base => $self->groupsDn,
                 filter => $filter,
                 scope => 'one',
                 attrs => ['cn', 'gidNumber']
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    my @groups;
    foreach my $entry ($result->entries) {
        if (not $system) {
            next if ($entry->get_value('gidNumber') < MINGID);
        }
        push @groups, $entry->get_value('cn');
    }

    return \@groups;
}

# Method: usersInGroup
#
#       Given a group it returns all the users belonging to it
#
# Parameters:
#
#       group - group name
#
# Returns:
#
#       array ref - holding the users
#
# Exceptions:
#
#       DataNorFound - If group does not  exist
sub usersInGroup # (group)
{
    my ($self, $group) = @_;

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

# Method: usersNotInGroup
#
#       Given a group it returns all the users who not belonging to it
#
# Parameters:
#
#       group - group name
#
# Returns:
#
#       array  - holding the groups
#
sub usersNotInGroup # (group)
{
    my ($self, $groupname) = @_;

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


# Method: gidGroup
#
#       Given a gid number it returns its group name
#
# Parameters:
#
#       gid - gid number
#
# Returns:
#
#       string - group name
#
sub gidGroup # (gid)
{
    my ($self, $gid) = @_;

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

# Method: groupGid
#
#       Given a group name  it returns its gid number
#
# Parameters:
#
#       group - group name
#
# Returns:
#
#       string - gid number
#
sub groupGid # (group)
{
    my ($self, $group) = @_;

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

sub _groupIsEmpty
{
    my ($self, $group) = @_;

    my @users = @{$self->usersInGroup($group)};

    return @users ? undef : 1;
}

sub _changeAttribute
{
    my ($self, $dn, $attr, $value) = @_;

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

sub isHashed
{
    my ($pwd) = @_;
    return ($pwd =~ /^\{[0-9A-Z]+\}/);
}

sub _checkPwdLength
{
    my ($self, $pwd) = @_;

    if (isHashed($pwd)) {
        return;
    }

    if (length($pwd) > MAXPWDLENGTH) {
        throw EBox::Exceptions::External(
            __x("Password must not be longer than {maxPwdLength} characters",
            maxPwdLength => MAXPWDLENGTH));
    }
}

sub _checkName
{
    my ($name) = @_;

    if ($name =~ /^[\w\d\s_-]+\.?[\w\d\s_-]+$/) {
        return 1;
    } else {
        return undef;
    }
}

# Returns modules implementing LDAP user base interface
sub _modsLdapUserBase
{
    my ($self) = @_;

    my $global = EBox::Global->modInstance('global');
    my @names = @{$global->modNames};

    my @modules;
    foreach my $name (@names) {
         my $mod = EBox::Global->modInstance($name);

        if ($mod->isa('EBox::LdapModule')) {
            if ($mod->isa('EBox::Module::Service')) {
                if ($name ne $self->name()) {
                    $mod->configured() or
                        next;
                }
            }
            push (@modules, $mod->_ldapModImplementation);
        }
    }

    return \@modules;
}

# Method: allUserAddOns
#
#       Returns all the mason components from those modules implementing
#       the function _userAddOns from EBox::LdapUserBase
#
# Parameters:
#
#       user - username
#
# Returns:
#
#       array ref - holding all the components and parameters
#
sub allUserAddOns # (user)
{
    my ($self, $username) = @_;

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

# Method: allGroupAddOns
#
#       Returns all the mason components from those modules implementing
#       the function _groupAddOns from EBox::LdapUserBase
#
# Parameters:
#
#       group  - group name
#
# Returns:
#
#       array ref - holding all the components and parameters
#
sub allGroupAddOns
{
    my ($self, $groupname) = @_;

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

# Method: allLDAPIncludes
#
#       Returns all the ldap schemas requested by those modules implementing
#       the function _includeLDAPSchemas from EBox::LdapUserBase
#
# Returns:
#
#       array ref - holding all the schemas
#
sub allLDAPIncludes
{
    my ($self) = @_;

    my @modsFunc = @{$self->_modsLdapUserBase()};
    my @includes;
    foreach my $mod (@modsFunc) {
        foreach my $path (@{$mod->_includeLDAPSchemas}) {
            push (@includes,  $path) if ($path);
        }
    }

    #We removes duplicated elements
    my %temp = ();
    @includes = grep ++$temp{$_} < 2, @includes;

    return \@includes;
}

# Method: allLDAPAcls
#
#       Returns all the ldap acls requested by those modules implementing
#       the function _includeLDAPSchemas from EBox::LdapUserBase
#
# Returns:
#
#       array ref - holding all the acls
#
sub allLDAPAcls
{
    my ($self) = @_;

    my @modsFunc = @{$self->_modsLdapUserBase()};
    my @allAcls;
    foreach my $mod (@modsFunc) {
        foreach my $acl (@{$mod->_includeLDAPAcls}) {
            push (@allAcls,  $acl) if ($acl);
        }
    }

    return \@allAcls;
}

# Method: allWarning
#
#       Returns all the the warnings provided by the modules when a certain
#       user or group is going to be deleted. Function _delUserWarning or
#       _delGroupWarning is called in all module implementing them.
#
# Parameters:
#
#       object - Sort of object: 'user' or 'group'
#       name - name of the user or group
#
# Returns:
#
#       array ref - holding all the warnings
#
sub allWarnings
{
    my ($self, $object, $name) = @_;

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

# Method: isRunning
#
#       Overrides EBox::ServiceModule::ServiceInterface method.
#
sub isRunning
{
    my ($self) = @_;
    return $self->isEnabled();
}

# Method: _supportActions
#
#       Overrides EBox::ServiceModule::ServiceInterface method.
#
sub _supportActions
{
    return undef;
}

# Method: menu
#
#       Overrides EBox::Module method.
#
sub menu
{
    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder('name' => 'Users',
                                        'text' => __('Users'),
                                        'separator' => __('Office'),
                                        'order' => 510);
    $folder->add(new EBox::Menu::Item('url' => 'UsersAndGroups/Users',
                                      'text' => __('Add User')));
    $folder->add(new EBox::Menu::Item(
                                      'url' => '/Users/View/Users',
                                      'text' => __('Edit User')));
    $root->add($folder);

    $folder = new EBox::Menu::Folder('name' => 'Group',
                                     'text' => __('Groups'),
                                     'separator' => __('Office'),
                                     'order' => 520);
    $folder->add(new EBox::Menu::Item('url' => 'UsersAndGroups/Groups',
                                    'text' => __('Add Group')));
    $folder->add(new EBox::Menu::Item('url' => 'Users/View/Groups',
                                    'text' => __('Edit Group')));

    $root->add($folder);
}

# EBox::UserCorner::Provider implementation

# Method: userMenu
#
sub userMenu
{
    my ($self, $root) = @_;

    $root->add(new EBox::Menu::Item('url' => '/Users/View/Password',
                                      'text' => __('Password')));
}

# LdapModule implementation
sub _ldapModImplementation
{
    return new EBox::LdapUserImplementation();
}





sub dumpConfig
{
  my ($self, $dir, %options) = @_;

  $self->{ldap}->dumpLdapData($dir);

  if ($options{bug}) {
    my $file = $self->{ldap}->ldifFile($dir);
    $self->_removePasswds($file);
  }
}


sub restoreConfig
{
  my ($self, $dir) = @_;

  $self->{ldap}->importLdapData($dir);
}



sub _removePasswds
{
  my ($self, $file) = @_;

  my $tmpFile = "/tmp/ea";


  my $anyPasswdAttr = any(qw(
                              userPassword
                              sambaLMPassword
                              sambaNTPassword
                            )
                         );
  my $passwordSubstitution = "password";

  my $FH_IN;
  my $FH_OUT;

  open $FH_IN, "<$file" or
    throw EBox::Exceptions::Internal ("Cannot open $file: $!");
  open $FH_OUT, ">$tmpFile" or
    throw EBox::Exceptions::Internal ("Cannot open $tmpFile: $!");

  foreach my $line (<$FH_IN>) {
    my ($attr, $value) = split ':', $line;
    if ($attr eq $anyPasswdAttr) {
      $line = $attr . ': ' . $passwordSubstitution . "\n";
    }

    print $FH_OUT $line;
  }

  close $FH_IN  or
    throw EBox::Exceptions::Internal ("Cannot close $file: $!");
  close $FH_OUT or
    throw EBox::Exceptions::Internal ("Cannot close $tmpFile: $!");

  File::Copy::move($tmpFile, $file);
  unlink $tmpFile;
}


sub minUid
{
    return MINUID;
}

sub minGid
{
    return MINGID;
}


sub defaultGroup
{
    return DEFAULTGROUP;
}

# Method: authUser
#
#   try to authenticate the given user with the given password
#
sub authUser
{
    my ($self, $user, $password) = @_;
    my $ldap = Net::LDAP->new(EBox::Ldap::LDAPI);
    $ldap or return undef;
    my $res = $ldap->bind($self->userDn($user), password => $password);
    return ($res->{'resultCode'} == 0);
}

sub shaHasher
{
    my ($password) = @_;
    return '{SHA}' . Digest::SHA1::sha1_base64($password) . '=';
}

sub md5Hasher
{
    my ($password) = @_;
    return '{MD5}' . Digest::MD5::md5_base64($password) . '==';
}

sub lmHasher
{
    my ($password) = @_;
    return Crypt::SmbHash::lmhash($password);
}

sub ntHasher
{
    my ($password) = @_;
    return Crypt::SmbHash::nthash($password);
}

sub digestHasher
{
    my ($password, $user) = @_;
    my $realm = getRealm();
    my $digest = "$user:$realm:$password";
    return '{MD5}' . Digest::MD5::md5_base64($digest) . '==';
}

sub realmHasher
{
    my ($password, $user) = @_;
    my $realm = getRealm();
    my $digest = "$user:$realm:$password";
    return '{MD5}' . Digest::MD5::md5_hex($digest);
}

sub getRealm
{
    # FIXME get the LDAP dc as realm when merged iclerencia/ldap-jaunty-ng
    return 'ebox';
}

sub passwordHasher
{
    my ($format) = @_;

    my $hashers = {
        'sha1' => \&shaHasher,
        'md5' => \&md5Hasher,
        'lm' => \&lmHasher,
        'nt' => \&ntHasher,
        'digest' => \&digestHasher,
        'realm' => \&realmHasher,
    };
    return $hashers->{$format};
}

sub defaultPasswordHash
{
    my ($password) = @_;

    my $format = EBox::Config::configkey('default_password_format');
    if (not defined($format)) {
        $format = 'shashaHa';
    }
    my $hasher = passwordHasher($format);
    my $hash = $hasher->($password);
    return $hash;
}

1;