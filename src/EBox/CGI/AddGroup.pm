package EBox::CGI::UsersAndGroups::AddGroup;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Users/Index";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;

	my $users = EBox::Global->modInstance('usersandgroups');

	$users->addGroup({
		name => $self->param('groupname'),
		gid => $self->param('gid'),
		desc => $self->param('groupdescription')});
}

1;
