package EBox::CGI::UsersAndGroups::AddUser;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::UsersAndGroups;
use EBox::Gettext;
use EBox::Exceptions::External;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Users and Groups',
				      @_);

	bless($self, $class);
	return $self;
}


sub _process($) {
	my $self = shift;
	my $usersandgroups = EBox::Global->modInstance('users');

	my @args = ();

	use Data::Dumper;
	print STDERR Dumper($self->{cgi});

	$self->_requireParam('username', __('user name'));
	$self->_requireParam('password', __('password'));
	$self->_requireParam('repassword', __('retype password'));
	$self->_requireParam('group', __('group'));
	$self->_requireParam('comment', __('comment'));
	
	my $user = $self->param('username');
	my $password = $self->param('password');
	my $repassword = $self->param('repassword');
	my $group = $self->param('group');
	my $comment = $self->param('comment');

	
	if ($password ne $repassword){
		 throw EBox::Exceptions::External(__('Passwords do'.
                                                     ' not match.'));
	}


	$usersandgroups->addUser($user, $password, $group, $comment);

	# FIXME Is there a better way to pass parameters to redirect/chain
	# cgi's
        #$self->{redirect} = "UsersAndGroups/Group?group=$group";
}


1;
