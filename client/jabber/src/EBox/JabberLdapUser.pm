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

package EBox::JabberLdapUser;

use strict;
use warnings;

use EBox::Sudo qw( :all );
use EBox::Global;
use EBox::Ldap;
use EBox::Network;
use EBox::Exceptions::Internal;
use EBox::Model::ModelManager;
use EBox::Gettext;
use EBox::UsersAndGroups;

use base qw(EBox::LdapUserBase);

sub new
{
	my $class = shift;
	my $self  = {};
	$self->{ldap} = EBox::Ldap->instance();
	$self->{jabber} = EBox::Global->modInstance('jabber');
	bless($self, $class);
	return $self;
}

sub _userAddOns
{
	my ($self, $username) = @_;

	return unless ($self->{jabber}->configured());

	my $active = 'no';
	$active = 'yes' if ($self->hasAccount($username));

	my $is_admin = 0;
	$is_admin = 1 if ($self->isAdmin($username));

	my @args;
	my $args = {
		    'username' => $username,
	             'active'   => $active,
		     'is_admin' => $is_admin,

		     'service' => $self->{jabber}->isEnabled(),
		   };

	return { path => '/jabber/jabber.mas',
		 params => $args };
}

sub schemas
{
	return [ EBox::Config::share() . 'ebox-jabber/jabber.ldif' ]
}

sub localAttributes
{
	return [ 'jabberUid' ];
}

sub isAdmin #($username)
{
    my ($self, $username) = @_;
	my $global = EBox::Global->getInstance(1);
	my $users = $global->modInstance('users');
	my $dn = $users->usersDn;
	my $active = '';
	my $is_admin = 0;

	$users->{ldap}->ldapCon;
	my $ldap = $users->{ldap};

	my %args = (base => $dn,
		    filter => "jabberUid=$username");
	my $mesg = $ldap->search(\%args);

	if ($mesg->count != 0){
	    foreach my $item (@{$mesg->entry->{'asn'}->{'attributes'}}){
		return 1 if (($item->{'type'} eq 'jabberAdmin') &&
			     (shift(@{$item->{'vals'}}) eq 'TRUE'));
	    }
	}
	return 0;
}

sub setIsAdmin #($username, [01]) 0=disable, 1=enable
{
        my ($self, $username, $option) = @_;
	my $global = EBox::Global->getInstance(1);

	return unless ($self->isAdmin($username) xor $option);

	my $users = $global->modInstance('users');
	my $dn = "uid=$username,".$users->usersDn;

	$users->{ldap}->ldapCon;
	my $ldap = $users->{ldap};

	my %args = (base => $dn,
		    filter => "jabberUid=$username");
	my $mesg = $ldap->search(\%args);

	if ($mesg->count != 0){
	    if ($option){
	    	my %attrs = (
		      changes => [
				   replace => [
					       jabberAdmin => 'TRUE'
					       ]
				   ]
		      );
		my $result = $ldap->modify($dn, \%attrs );
		($result->is_error) and
		    throw EBox::Exceptions::Internal('Error updating user: $username\n\n');
		$global->modChange('jabber');
	    } else {
	        my %attrs = (
			      changes => [
					   replace => [
						       jabberAdmin => 'FALSE'
						       ]
					   ]
			      );
		my $result = $ldap->modify($dn, \%attrs );
		($result->is_error) and
		    throw EBox::Exceptions::Internal('Error updating user: $username\n\n');
		$global->modChange('jabber');
	    }
	}

	return 0;
}

sub hasAccount #($username)
{
        my ($self, $username) = @_;
	my $global = EBox::Global->getInstance(1);
	my $users = $global->modInstance('users');
	my $dn = $users->usersDn;

	$users->{ldap}->ldapCon;
	my $ldap = $users->{ldap};

	my %args = (base => $dn,
		    filter => "jabberUid=$username");
	my $mesg = $ldap->search(\%args);

	return 1 if ($mesg->count != 0);
	return 0;
}

sub setHasAccount #($username, [01]) 0=disable, 1=enable
{
        my ($self, $username, $option) = @_;
	my $global = EBox::Global->getInstance(1);
	my $users = $global->modInstance('users');
	my $dn = "uid=$username," . $users->usersDn;

	$users->{ldap}->ldapCon;
	my $ldap = $users->{ldap};

	my %args = (base => $dn,
		    filter => "jabberUid=$username");
	my $mesg = $ldap->search(\%args);

	if (!$mesg->count and ($option)){
	    my %attrs = (
			  changes => [
				       add => [
					       objectClass => 'userJabberAccount',
					       jabberUid   => $username,
					       jabberAdmin => 'FALSE'
					       ]
				       ]
			  );
	    my $result = $ldap->modify($dn, \%attrs );
	    ($result->is_error) and
		throw EBox::Exceptions::Internal('Error updating user: $username\n\n');
	} elsif ($mesg->count and not ($option)) {
	    my %attrs = (
			  changes => [
				       delete => [
						  objectClass => ['userJabberAccount'],
						  jabberUid   => [$username],
						  jabberAdmin => []
						  ]
				       ]
			  );
	    my $result = $ldap->modify($dn, \%attrs );
	    ($result->is_error) and
		throw EBox::Exceptions::Internal('Error updating user: $username\n\n');
	}

	return 0;
}

sub getJabberAdmins
{
        my $self = shift;
	my $global = EBox::Global->getInstance(1);
	my $users = $global->modInstance('users');
	my $dn = $users->usersDn;
	my @admins = ();

	$users->{ldap}->ldapCon;
	my $ldap = $users->{ldap};

	my %args = (base => $dn,
		    filter => "jabberAdmin=TRUE");
	my $mesg = $ldap->search(\%args);

	foreach my $entry ($mesg->entries) {
	    foreach my $attrib (@{$entry->{'asn'}->{'attributes'}}){
		if ($attrib->{'type'} eq 'jabberUid'){
		    push (@admins, pop(@{$attrib->{'vals'}}));
		}
	    }
	}

	return @admins;
}


sub _addUser
{
   my ($self, $user, $password) = @_;

   unless ($self->{jabber}->configured()) {
       return;
   }
   my $model = EBox::Model::ModelManager::instance()->model('jabber/JabberUser');
   $self->setHasAccount($user, $model->enabledValue());
}


sub _delUserWarning
{
    my ($self, $user) = @_;

    return unless ($self->{jabber}->configured());

    $self->hasAccount($user) or
        return;

    settextdomain('ebox-jabber');
    my $txt = __('This user has a jabber account. If the user currently connected it will continue connected until jabber authorization is again required.');
    settextdomain('ebox-usersandgroups');

    return $txt;
}

# Method: defaultUserModel
#
#   Overrides <EBox::UsersAndGrops::LdapUserBase::defaultUserModel>
#   to return our default user template
sub defaultUserModel
{
    return 'jabber/JabberUser';
}


1;
