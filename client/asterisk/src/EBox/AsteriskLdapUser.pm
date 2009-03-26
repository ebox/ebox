# Copyright (C) 2009 eBox Technologies S.L.
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

# Class: EBox::AsteriskLdapUser
#
#

package EBox::AsteriskLdapUser;

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;
use EBox::Ldap;
use EBox::UsersAndGroups;
use EBox::Asterisk::Extensions;

use base qw(EBox::LdapUserBase);

use constant SCHEMAS => ('/etc/ldap/schema/asterisk.schema');


sub new
{
    my $class = shift;
    my $self  = {};
    $self->{ldap} = EBox::Ldap->instance();
    $self->{asterisk} = EBox::Global->modInstance('asterisk');
    bless($self, $class);
    return $self;
}


# Method: _addUser
#
# Implements:
#
#       <EBox::LdapUserBase::_addUser>
#
sub _addUser
{
    my ($self, $user) = @_;

    unless ($self->{asterisk}->configured()) {
        return;
    }

    my $users = EBox::Global->modInstance('users');
    my $ldap = $self->{ldap};

    my $dn = "uid=$user," . $users->usersDn;

    my $extensions = new EBox::Asterisk::Extensions;

    my $extn = $extensions->firstFreeExtension();

    my %attrs = (changes => [
                             add => [
                                     objectClass => 'AsteriskSIPUser',
                                     AstAccountContext => 'default',
                                     AstAccountCallerID => $extn,
                                     AstAccountHost => 'dynamic',
                                     AstAccountIPAddress => '0.0.0.0',
                                     AstAccountPort => '0',
                                     AstAccountExpirationTimestamp => '0',
                                     AstAccountUserAgent => '0',
                                     AstAccountFullContact => 'sip:0.0.0.0',
                                     objectClass => 'AsteriskVoicemail',
                                     AstAccountMailbox => $extn, #FIXME random?
                                     AstAccountVMPassword => $extn,
                                    ],
                            ]
                );

    my %args = (base => $dn, filter => 'objectClass=AsteriskSIPUser');
    my $result = $ldap->search(\%args);

    unless ($result->count > 0) {
        $ldap->modify($dn, \%attrs);
        if ($extn > 0) { $extensions->addUserExtension($user, $extn); }
    }
}


# Method: _userAddOns
#
# Implements:
#
#       <EBox::LdapUserBase::_userAddOns>
#
sub _userAddOns
{
    my ($self, $username) = @_;
    my $asterisk = $self->{asterisk};

    return unless ($asterisk->configured());

    my $active = 'no';
    $active = 'yes' if ($self->hasAccount($username));

    my $extensions = new EBox::Asterisk::Extensions;
    my $extension = $extensions->getUserExtension($username);

    my $args = {
        'username' => $username,
        'extension' => $extension,
        'active'   => $active,
        'service' => $asterisk->isEnabled(),
    };

    return { path => '/asterisk/asterisk.mas',
             params => $args };
}


# Method: _delUser
#
# Implements:
#
#       <EBox::LdapUserBase::_delUser>
#
sub _delUser
{
    my ($self, $user) = @_;

    unless ($self->{asterisk}->configured()) {
        return;
    }

    my $extensions = new EBox::Asterisk::Extensions;
    $extensions->delUserExtension($user);

    my $users = EBox::Global->modInstance('users');
    my $uid = $users->userInfo($user)->{uid};

    # Delete LDAP info
    my $ldap = $users->{ldap};
    my $dn = "uid=$user," . $users->usersDn;

    $ldap->delObjectclass($dn, 'AsteriskSIPUser');
    $ldap->delObjectclass($dn, 'AsteriskVoicemail');

    # TODO: Implement also _delUserWarning ??
}


# Method: _includeLDAPSchemas
#
#   Those modules which need to use their own LDAP schemas must implement
#   this method. It must return an array with LDAP schemas.
#
# Returns:
#
#       an array ref - containing in each element the full path of the schema
#       schema file to be include.
#
sub _includeLDAPSchemas
{
    my ($self) = @_;

    unless ($self->{'asterisk'}->configured()) {
        return [];
    }

    my @schemas = SCHEMAS;

    return \@schemas;
}


# Method: _includeLDAPAcls
#
#   Those modules which need to use their own LDAP ACLs must implement
#   this method. It must return an array with LDAP ACLs.
#
# Returns:
#
#       an array ref - containing in each element an ACL for the LDAP
#       database.
#
sub _includeLDAPAcls {
        my $self = shift;

        return [] unless ($self->{'asterisk'}->configured());
        my $ldapconf = $self->{ldap}->ldapConf;

        my @acls = ("access to attrs=AstAccountVMPassword\n" .
                    "\tby dn.regex=\"" . $ldapconf->{'rootdn'} . "\" write\n" .
                    "\tby self write\n" .
                    "\tby * none\n");

        return \@acls;
}


sub setHasAccount #($username, [01]) 0=disable, 1=enable
{
    my ($self, $username, $option) = @_;

    if ($option) {
        $self->_addUser($username);
    } else {
        $self->_delUser($username);
    }
}


sub hasAccount #($username)
{
    my ($self, $username) = @_;

    my $users = EBox::Global->modInstance('users');
    my $ldap = $self->{ldap};

    my $dn = "uid=$username," . $users->usersDn;

    my %args = (base => $dn, filter => 'objectClass=AsteriskSIPUser');
    my $result = $ldap->search(\%args);

    return 1 if ($result->count != 0);
    return 0;
}

1;
