package EBox::CGI::UsersAndGroups::Group;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::UsersAndGroups;
use EBox::Gettext;


sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Users and Groups',
				      'template' => '/usersandgroups/group.mas',
				      @_);
	bless($self, $class);
	return $self;
}


sub _process($) {
	my $self = shift;
	my $usersandgroups = EBox::Global->modInstance('users');

	my @args = ();

	$self->_requireParam('group', __('group'));
	
	my $group = $self->param('group');
	my @grpusers = $usersandgroups->getGroupUsers($group);
	my @remainusers = $usersandgroups->getUsersNotInGroup($group);

	push(@args, 'group' => $group);
	push(@args, 'groupusers' => \@grpusers);
	push(@args, 'remainusers' => \@remainusers);

	$self->{params} = \@args;
}


1;
