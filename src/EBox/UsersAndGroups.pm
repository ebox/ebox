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


sub addGroup($$){
	my $self = shift;

	my $groupref = shift;

	$self->{ldap}->addGroup($groupref);
}


sub delGroup($$){
	my $self = shift;

	my $groupname = shift;

	$self->{ldap}->delGroup($groupname);
}


sub modifyGroup($$$){
	my $self = shift;

	my $groupname = shift;
	my $groupref = shift;

	$self->{ldap}->modifyGroup($groupname, $groupref);
}


sub addUser($$){
	my $self = shift;

	my $userref = shift;

	$self->{ldap}->addUser($userref);
}


sub delUser($$){
	my $self = shift;

	my $username = shift;

	$self->{ldap}->delUser($username);
}


# FIXME WArNING cutre paste 
#sub modifyUser($$$){
#	my $self = shift;

#	my $groupname = shift;
#	my $groupref = shift;

#	$self->{ldap}->modifyGroup($groupname, $groupref);
#}


1;
