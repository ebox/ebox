package EBox::CGI::UsersAndGroups::User;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::UsersAndGroups;
use EBox::Gettext;


sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Users and Groups',
				      'template' => '/usersandgroups/user.mas',
				      @_);
	bless($self, $class);
	return $self;
}


sub _process($) {
	my $self = shift;
	my $usersandgroups = EBox::Global->modInstance('users');

	my @args = ();

	$self->_requireParam("user", __('user'));

	my $user = $self->param('user');
	my $userinfo = $usersandgroups->getUserInfo($user);
		
	push(@args, 'user' => $userinfo);


	$self->{params} = \@args;
}


1;
