package EBox::CGI::UsersAndGroups::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::UsersAndGroups;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Users and Groups',
				      'template' => '/users/index.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $usersandgroups = EBox::Global->modInstance('usersandgroups');

	my @args = ();

	my @groups = $usersandgroups->getGroups();
	my @users = $usersandgroups->getUsers();

	
	push(@args, {'groups' => \@groups});
	push(@args, {'users' => \@users});

#	push(@args, {'groups' => $usersandgroups->getGroups()});
#	push(@args, {'users' => $usersandgroups->getUsers()});

	if (defined $self->param("show")) {
		push(@args, {'show' => $self->param('show')});
	} else {
		push(@args, {'show' => ""});
	}

	$self->{params} = \@args;
}

1;
