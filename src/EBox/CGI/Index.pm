package EBox::CGI::UsersAndGroups::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::UsersAndGroups;


sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Users and Groups',
				      'template' => '/usersandgroups/index.mas',
				      @_);
	bless($self, $class);
	return $self;
}


sub _process($) {
	my $self = shift;
	my $usersandgroups = EBox::Global->modInstance('users');
	my $objects = EBox::Global->modInstance('objects');

	my @args = ();

	my @groups = $usersandgroups->getGroups();
	my @users = $usersandgroups->getUsers();

	push(@args, 'groups' => \@groups);
	push(@args, 'users' => \@users);


	$self->{params} = \@args;
}


1;
