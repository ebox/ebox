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

package EBox::MailUserLdap;

use strict;
use warnings;

use EBox::Sudo qw( :all );
use EBox::Global;
use EBox::Ldap;
use EBox::Validate qw( :all );
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Gettext;

use Perl6::Junction qw(any);

# LDAP schema
use constant DIRVMAIL   =>      '/var/vmail/';
use constant BYTES                              => '1048576';
use constant MAXMGSIZE                          => '104857600';

use base qw(EBox::LdapUserBase);

sub new
{
    my $class = shift;
    my $self  = {};
    $self->{ldap} = EBox::Ldap->instance();

    bless($self, $class);
    return $self;
}

# Method: mailboxesDir
#
#  Returns:
#    directory where the mailboxes resides
sub mailboxesDir
{
    return DIRVMAIL;
}


# Method: setUserAccount
#
#  This method sets a mail account to a user.
#  The user may be a system user
#
# Parameters:
#
#               user - username
#               lhs - the left hand side of a mail (the foo on foo@bar.baz account)
#               rhs - the right hand side of a mail (the bar.baz on previus account)

sub setUserAccount
{
    my ($self, $user, $lhs, $rhs)  = @_;

    my $ldap = $self->{ldap};
    my $users = EBox::Global->modInstance('users');
    my $mail = EBox::Global->modInstance('mail');
    my $email = $lhs.'@'.$rhs;

    unless ($email =~ /^[^\.\-][\w\.\-]+\@[^\.\-][\w\.\-]+$/) {
        throw EBox::Exceptions::InvalidData('data' => __('mail account'),
                                            'value' => $email);
    }

    if ($mail->{malias}->accountExists($email)) {
        throw EBox::Exceptions::DataExists('data' => __('mail account'),
                                           'value' => $email);
    }

    $self->_checkMaildirNotExists($lhs, $rhs);


    
    my $quota = $mail->defaultMailboxQuota();
    my $dn = "uid=$user," .  $users->usersDn;

        my %attrs = (
                     changes => [
                                 add => [
                                         objectClass => 'couriermailaccount',
                                         objectClass => 'usereboxmail',
                                         mail            => $email,
                                         mailbox => $rhs.'/'.$lhs.'/',
                                         userMaildirSize    => 0,
                                         quota           => $quota,
                                         mailHomeDirectory => DIRVMAIL
                                        ]
                                ]
                    );
        my $add = $ldap->modify($dn, \%attrs );

    
    $self->_createMaildir($lhs, $rhs);

    my @list = $mail->{malias}->listMailGroupsByUser($user);
    
    foreach my $item(@list) {
        my $alias = $mail->{malias}->groupAlias($item);
        $mail->{malias}->addMaildrop($alias, $email);
    }

}

# Method: delUserAccount
#
#  This method removes a mail account to a user
#
# Parameters:
#
#               username - username
#               usermail - the user's mail address (optional)
sub delUserAccount   #username, mail
{
    my ($self, $username, $usermail) = @_;
 
    ($self->_accountExists($username)) or return;

    if (not defined $usermail) {
        $usermail = $self->userAccount($username);
    }

    my $mail = EBox::Global->modInstance('mail');
    my $users = EBox::Global->modInstance('users');

    # First we remove all mail aliases asociated with the user account.
    foreach my $alias ($mail->{malias}->accountAlias($usermail)) {
                $mail->{malias}->delAlias($alias);
            }

    # Remove mail account from group alias maildrops
    foreach my $alias ($mail->{malias}->groupAccountAlias($usermail)) {
        $mail->{malias}->delMaildrop($alias,$usermail);
    }

    # get the mailbox attribute for later use..
    my $mailbox = $self->getUserLdapValue($username, "mailbox");

    # Now we remove all mail atributes from user ldap leaf
    my @toDelete = (
                    mail                    => $self->getUserLdapValue($username, "mail"),
                    mailbox                 => $mailbox,
                    userMaildirSize            => 
                        $self->getUserLdapValue($username, "userMaildirSize"),
                    quota                   => 
                        $self->getUserLdapValue($username, "quota"),

                    mailHomeDirectory => $self->getUserLdapValue($username, "mailHomeDirectory"),
                    objectClass     => 'couriermailaccount',
                    objectClass => 'usereboxmail',
                   );





    my %attrs = (
                 changes => [
                             delete => \@toDelete,
                            ]
                );

    my $ldap = $self->{ldap};
    my $dn = "uid=$username," .  $users->usersDn;
    $ldap->modify($dn, \%attrs );

    # Here we remove mail directorie of user account.
    root("/bin/rm -rf ".DIRVMAIL.$mailbox);

}


# Method: userAccount
#
#  return the user mail account or undef if it doesn't exists
#
sub userAccount
{
    my ($self, $username) = @_;

    my $mail = EBox::Global->modInstance('mail');
    my $users = EBox::Global->modInstance('users');

    my %args = (
                base => $users->usersDn,
                filter => "&(objectclass=*)(uid=$username)",
                scope => 'one',
                attrs => ['mail'],
                active => $mail->service,
               );

    my $result = $self->{ldap}->search(\%args);
    my $entry = $result->entry(0);

    my $usermail = $entry->get_value('mail');

    return $usermail;
}


# Method: delAccountsFromVDomain
#
#  This method removes all mail accounts from a virtual domain
#
# Parameters:
#
#               vdomain - the virtual domain name
sub delAccountsFromVDomain   #vdomain
{
    my ($self, $vdomain) = @_;

    my %accs = %{$self->allAccountsFromVDomain($vdomain)};

    my $mail = "";
    foreach my $uid (keys %accs) {
                $mail = $accs{$uid};
                $self->delUserAccount($uid, $accs{$uid});
        }
}

# Method: getUserLdapValue
#
#  This method returns the value of an atribute in users leaf
#
# Parameters:
#
#               uid - uid of the user
#               value - the atribute name
sub getUserLdapValue   #uid, ldap value
{
    my ($self, $uid, $value) = @_;
    my $users = EBox::Global->modInstance('users');

    my %args = (
                base => $users->usersDn(),
                filter => "&(objectclass=*)(uid=$uid)",
                scope => 'one',
                attrs => [$value]
               );

    my $result = $self->{ldap}->search(\%args);
    my $entry = $result->entry(0);

    return $entry->get_value($value);
}

# Method: setUserLdapValue
#
#  This method sets the value of a single-valued attribute in users leaf
#
# Parameters:
#
#               uid - uid of the user
#               attr  - the atribute name
#               value - new value for the attribute
#  

sub setUserLdapValue
{
    my ($self, $user, $attr, $value) = @_;

    my $ldap = $self->{ldap};
    my $users =EBox::Global->modInstance('users');
    my $dn = "uid=$user," .  $users->usersDn;
    $ldap->setAttribute($dn, $attr, $value);

}

# Method: existsUserLdapValue
#
#  This method returns wether an attribute exists in users leaf
#
# Parameters:
#
#               uid - uid of the user
#               value - the atribute name
#  
#  Returns:
#          - boolean
sub existsUserLdapValue
{
    my ($self, $uid, $value) = @_;
    my $users = EBox::Global->modInstance('users');

    my %args = (
                        base => $users->usersDn(),
                filter => "&(objectclass=*)(uid=$uid)",
                scope => 'one',
                attrs => [$value]
               );

    my $result = $self->{ldap}->search(\%args);

        foreach my $entry ($result->entries()) {
            if (defined ($entry->get_value($value))) {
                return 1;
            }
        }

    return undef;
}



sub _delGroup
{
    my ($self, $group) = @_;

    return unless (EBox::Global->modInstance('mail')->configured());

    my $mail = EBox::Global->modInstance('mail');
    $mail->{malias}->delAliasGroup($group);

}

sub _delGroupWarning
{
    my ($self, $group) = @_;

    return unless (EBox::Global->modInstance('mail')->configured());

    my $mail = EBox::Global->modInstance('mail');

        settextdomain('ebox-mail');
    my $txt = __('This group has a mail alias');
    settextdomain('ebox-usersandgroups');

        if ($mail->{malias}->groupHasAlias($group)) {
            return ($txt);
        }

    return undef;
}


sub _delUser
{
    my ($self, $user) = @_;

    return unless (EBox::Global->modInstance('mail')->configured());

    $self->delUserAccount($user);
}

sub _delUserWarning
 {
     my ($self, $user) = @_;

     return unless (EBox::Global->modInstance('mail')->configured());

     settextdomain('ebox-mail');
     my $txt = __('This user has a mail account');
     settextdomain('ebox-usersandgroups');

     if ($self->_accountExists($user)) {
         return ($txt);
     }

     return undef;
}

sub _userAddOns
 {
     my ($self, $username) = @_;

     my $mail = EBox::Global->modInstance('mail');

     return undef unless ($mail->configured());

     my $usermail = $self->userAccount($username);
     my @aliases = $mail->{malias}->accountAlias($usermail);
     my @vdomains =  $mail->{vdomains}->vdomains();
     my $quotaType = $self->maildirQuotaType($username);
     my $quota   = $self->maildirQuota($username);

     my @paramsList = (
                       username    =>      $username,
                       mail        =>      $usermail,
                       aliases     => \@aliases,
                       vdomains    => \@vdomains,
                       
                       maildirQuotaType => $quotaType,
                       maildirQuota => $quota,
                       
                       service => $mail->service,
                      );



     return { path => '/mail/account.mas', params => { @paramsList } };
 }





sub _groupAddOns
 {
     my ($self, $group) = @_;

     return unless (EBox::Global->modInstance('mail')->configured());

     my $mail = EBox::Global->modInstance('mail');
     my $users = EBox::Global->modInstance('users');


     my %args = (
                 base => $mail->{malias}->aliasDn,
                 filter => "&(objectclass=*)(uid=$group)",
                 scope => 'one',
                 attrs => ['mail'],
                 service => $mail->service,
                );

     my $alias = undef;
     my $result = $self->{ldap}->search(\%args);


     if ($result->count > 0) {
         my $entry = $result->entry(0);
         $alias = $entry->get_value('mail');
     }

     my @vd =  $mail->{vdomains}->vdomains();

     my $args = {    'group' => $group,
                        'vdomains'      =>      \@vd,
                     'alias'         => $alias,
                     'nacc' => scalar ($self->usersWithMailInGroup($group)),
                };

     return { path => '/mail/groupalias.mas', params => $args };
}

sub _modifyGroup
 {
     my ($self, $group) = @_;

     return unless (EBox::Global->modInstance('mail')->configured());

     my $mail = EBox::Global->modInstance('mail');

     my %args = (
                base => $mail->{malias}->aliasDn,
                 filter => "&(objectclass=couriermailalias)(uid=$group)",
                 scope => 'one',
                 attrs => ['mail']
                );

     my $result = $self->{ldap}->search(\%args);

     if($result->count > 0) {
         my $alias = ($result->sorted('mail'))[0]->get_value('mail');
         $mail->{malias}->updateGroupAlias($group, $alias);
     }

 }

# Method: _accountExists
#
#  This method returns if a user have a mail account
#
# Parameters:
#
#               username - username
# Returnss:
#
#               bool - true if user have mail account
sub _accountExists
{
    my ($self, $username) = @_;

    my $users = EBox::Global->modInstance('users');

    my %attrs = (
                 base => $users->usersDn,
                 filter => "&(objectclass=couriermailaccount)(uid=$username)",
                 scope => 'one'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    return ($result->count > 0);

}


# Method: allAccountFromVDomain
#
#  This method returns all accounts from a virtual domain
#
# Parameters:
#
#               vdomain - The Virtual domain name
#
# Returns:
#
#               hash ref - with (uid, mail) pairs of the virtual domain
sub allAccountsFromVDomain
{
    my ($self, $vdomain) = @_;

    my $users = EBox::Global->modInstance('users');

    my %attrs = (
                 base => $users->usersDn,
                 filter => "&(objectclass=couriermailaccount)(mail=*@".$vdomain.")",
                 scope => 'one'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    my %accounts = map { $_->get_value('uid'), $_->get_value('mail')} $result->sorted('uid');

    return \%accounts;
}

# Method: usersWithMailInGroup
#
#  This method returns the list of users with mail account on the group
#
# Parameters:
#
#               groupname - groupname
#
sub usersWithMailInGroup
{
    my ($self, $groupname) = @_;
    my $users = EBox::Global->modInstance('users');

    my %args = (
                base => $users->usersDn,
                filter => "(objectclass=couriermailaccount)",
                scope => 'one',
               );

    my $result = $self->{ldap}->search(\%args);

    my @mailusers;
    foreach my $entry ($result->entries()) {
        push @mailusers, $entry->get_value('uid');
    }

    my $anyUserInGroup = any( @{ $users->usersInGroup($groupname) } );

    # the intersection between users with mail and users of the group
    my @mailingroup = grep {
        $_ eq $anyUserInGroup
    } @mailusers;

    return @mailingroup;
}

# Method: checkUserMDSize
#
#  This method returns all users that should be warned about a reduction on the
#  maildir size
#
# Parameters:
#
#               vdomain - The Virtual domain name
#               newmdsize - The new maildir size
sub checkUserMDSize
{
    my ($self, $vdomain, $newmdsize) = @_;

    my %accounts = %{$self->allAccountsFromVDomain($vdomain)};
    my @warnusers = ();
    my $size = 0;

    foreach my $acc (keys %accounts) {
        $size = $self->maildirQuota($acc);
                ($size > $newmdsize) and push (@warnusers, $acc);
    }

    return \@warnusers;
}


sub _checkMaildirNotExists
{
    my ($self, $lhs, $vdomain) = @_;
    my $dir = "/var/vmail/$vdomain/$lhs";

    if (EBox::Sudo::fileTest('-e', $dir)) {
        my $backupDir = $dir . '.bak';
        EBox::Sudo::root("mv $dir $backupDir");
        EBox::warn(
           "Mail directory $dir already existed, moving it to $backupDir"
                     );
    }

}

# Method: _createMaildir
#
#  This method creates the maildir of an account
#
# Parameters:
#
#               lhs - left hand side of an account (foo on foo@bar.baz)
#               vdomain - Virtual Domain name
sub _createMaildir
{
    my ($self, $lhs, $vdomain) = @_;
    my $vdomainDir = "/var/vmail/$vdomain";
    my $userDir   =  "$vdomainDir/$lhs/";

    root("/bin/mkdir -p /var/vmail");
    root("/bin/chmod 2775 /var/mail/");
    root("/bin/chown ebox.ebox /var/vmail/");

    root("/bin/mkdir -p $vdomainDir");
    root("/bin/chown ebox.ebox $vdomainDir");
    root("/usr/bin/maildirmake.dovecot $userDir ebox");
    root("/bin/chown ebox.ebox -R $userDir");
}



#  Method: maildir
#
#     get the maildir which will be used by the given account
#
#   Parameters:
#               lhs - left hand side of an account (foo on foo@bar.baz)
#               vdomain - Virtual Domain name
#
#   Returns:
#         full path of the maildir
sub maildir
{
  my ($class, $lhs, $vdomain) = @_;

  return "/var/vmail/$vdomain/$lhs/";
}

#  Method: maildirQuota
#
#     get the maildir quota for the user, please note that is only the quota
#     amount this does not signals wether it is a default quota or a custom quota
#
#   Parameters:
#        user - name of the user
sub maildirQuota
{
    my ($self, $user) = @_;
    return $self->getUserLdapValue($user, 'quota');
}

#  Method: maildirQuotaType
#
#     get the type of the quota assigned to the user
#
#   Parameters:
#        user - name of the user
#
#    Returns:
#       one of this strings:
#          'default' - uses default quota type
#          'noQuota' - the user has a custom unlimtied quota
#          'custom'  - the user has a non-unlimted custom quota
sub maildirQuotaType
{
    my ($self, $user)  = @_;
    
    my $userQuota = $self->getUserLdapValue($user, 'userMaildirSize');
    if ($userQuota == 0) {
        return 'default';
    }

    my $quota = $self->maildirQuota($user);
    if ($quota == 0) {
        return 'noQuota';
    } else {
        return 'custom';
    }

    return 'default';
}


#  Method: setMaildirQuotaUsesDefault
#
#     sets wether the user is using the default quota or not. Additionally if
#     user is set to use the default quota the quota value is synchronized with
#     the default quota
#
#   Parameters:
#        user - name of the user
#        isDefault - wether the user is using the default quota
sub setMaildirQuotaUsesDefault
{
    my ($self, $user, $isDefault) = @_;

    my $userMaildirSizeValue = $isDefault ? 0 : 1;
    $self->setUserLdapValue($user, 'userMaildirSize', $userMaildirSizeValue);
    if ($isDefault) {
       # sync quota with default
        my $mail = EBox::Global->modInstance('mail');
        my $defaultQuota = $mail->defaultMailboxQuota();
        $self->setUserLdapValue($user, 'quota', $defaultQuota);
    }
}



#  Method: setMaildirQuota
#
#     sets the quota value for a user. Do not use it with users which use
#     default quota; in this  case use only setMaildirQuotaUsesDefault
#
#   Parameters:
#        user - name of the user
#        quota - numeric value of the quota in Mb
sub setMaildirQuota
{
    my ($self, $user, $quota) = @_;
    defined $user or
        throw EBox::Exceptions::MissingArgument('user');
    defined $quota or
        throw EBox::Exceptions::MissingArgument('quota');
    
    if (not $self->userAccount($user)) {
        throws EBox::Exceptions::Internal(
             "User $user has not mail account"
           );
    }

    if ($quota < 0) {
        throw EBox::Exceptions::External(
            __('Quota can only be a postitive number or zero for unlimited quota')
           )
    }

    $self->setUserLdapValue($user, 'quota', $quota);

}

#  Method: regenMaildirQuotas
#
# regenerate user accounts mailquotas to reflect the changes in default
# quota configuration
sub regenMaildirQuotas
{
    my ($self) = @_;

    my $mail = EBox::Global->modInstance('mail');
    my $defaultQuota = $mail->defaultMailboxQuota();
    my $usersMod = EBox::Global->modInstance('users');

    foreach my $user ($usersMod->users()) {
        my $userName = $user->{username};
        $self->userAccount($userName) or
            next;

        if ($self->maildirQuotaType($userName) eq 'default') {
            $self->setMaildirQuota($userName, $defaultQuota);
        }
    }
}



# Method: gidvmail
#
#  This method returns the gid value of ebox user
#
sub gidvmail
 {
     my ($self) = @_;
     return scalar (getgrnam(EBox::Config::group));
}

# Method: uidvmail
#
#  This method returns the uid value of ebox user
#
sub uidvmail
{
    my ($self) = @_;

    return scalar (getpwnam(EBox::Config::user));
}

# Method: _isCourierObject
#
#  This method returns if the leaf have a courierobject class
#
sub _isCourierObject
 {
     my ($self, $object, $dn) = @_;

     my $ldap = $self->{ldap};

     my %attrs = (
                  base   => $dn,
                  filter => "(objectclass=$object)",
                  attrs  => [ 'objectClass'],
                  scope  => 'base'
                 );

     my $result = $ldap->search(\%attrs);

     if ($result->count ==  1) {
         return 1;
     }

     return undef;
}


sub _accountAddOn
{
    my ($self, $username) = @_;

    my $mail = EBox::Global->modInstance('mail');

}






sub schemas
{
    return [ EBox::Config::share() . '/ebox-mail/authldap.ldif',
             EBox::Config::share() . '/ebox-mail/eboxmail.ldif' ];
}

1;
