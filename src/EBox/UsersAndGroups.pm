=head1 NAME

EBox::UsersAndGroups - EBOX Users and groups module

=head1 DESCRIPTION

This module is used to manage users and groups 

=cut

package EBox::UsersAndGroups;

use strict;
use warnings;

use base 'EBox::Module';

use EBox::Global;

use EBox::Ldap;



my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

=head1 METHODS

=cut

sub _create {
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'usersandgroups');

	$self->{ldap} = new EBox::Ldap();

	bless($self, $class);
	return $self;
}


sub getGroups($) {
	my $self = shift;

	return $self->{ldap}->getGroups();
}


sub getUsers($) {
	my $self = shift;

	return $self->{ldap}->getUsers();
}

sub getUserInfo($$){
	my $self = shift;
	my $user = shift;

	return $self->{ldap}->getUserInfo($user);
}

sub addGroup($$){
	my $self = shift;

	my $group = shift;
	my $comment = shift;

	$self->{ldap}->addGroup($group, $comment);
}

sub addUserToGroup($$$){
	my $self = shift;
	my $user = shift;
	my $group = shift;
	
	$self->{ldap}->addUserToGroup($user, $group);
}

# Delete testing if group is empty
sub delGroup($$){
	my $self = shift;

	my $groupname = shift;

	my $gid = $self->{ldap}->getGroupGid($groupname);

	if ($self->{ldap}->groupHaveUsers($gid)) {
		throw EBox::Exceptions::DataExists('data' => __('Group'),
		                                  'value' => $groupname);
	} else {
		$self->{ldap}->delGroup($groupname);
	}

}

sub delUserFromGroup($$$){
	my $self = shift;
	my $user = shift;
	my $group = shift;
	
	$self->{ldap}->delUserFromGroup($user, $group);
}

sub getGroupUsers($$){
	my $self  = shift;
	my $groupname = shift;
	
	return $self->{ldap}->getGroupUsers($groupname);
	
}

sub getUsersNotInGroup($$){
	my $self  = shift;
	my $groupname = shift;
	
	my @grpusers = $self->{ldap}->getGroupUsers($groupname);
	my @allusers = $self->{ldap}->getUsers();

	my @users;
	foreach my $user (@allusers){
		my $uid = $user->{account};
		unless (grep (/^$uid$/, @grpusers)){
			push @users, $uid;
		}
	}

	return @users;
}

# Delete group with its users
sub delGroupWithUsers($$){
	my $self = shift;

	my $groupname = shift;

	my @users = $self->{ldap}->getGroupUsers($groupname);

	foreach (@users) {
		$self->{ldap}->delUser($_);
	}

	$self->{ldap}->delGroup($groupname);
}


sub modifyGroup($$$){
	my $self = shift;

	my $groupname = shift;
	my $groupref = shift;

	$self->{ldap}->modifyGroup($groupname, $groupref);

	# FIXME if gid is modified, modify users too
}


sub addUser($$){
	my $self = shift;

	$self->{ldap}->addUser(@_);
}


sub delUser($$){
	my $self = shift;

	my $username = shift;

	if ($self->{ldap}->isLastUser($username)) {
		throw EBox::Exceptions::DataMissing('data' => __('Group'));
	}

	$self->{ldap}->delUser($username);
}


sub delUserForce($$){
	my $self = shift;

	my $username = shift;

	$self->{ldap}->delUser($username);
}


sub delUserWithGroup($$){
	my $self = shift;

	my $username = shift;

	my $groupname = $self->{ldap}->getUserGroup($username);

	$self->{ldap}->delUser($username);
	
	$self->{ldap}->delGroup($groupname);
	
}


# FIXME WArNING cutre paste 
#sub modifyUser($$$){
#	my $self = shift;

#	my $groupname = shift;
#	my $groupref = shift;

#	$self->{ldap}->modifyGroup($groupname, $groupref);
#}


1;
