package EBox::CGI::UsersAndGroups::DelGroup;

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

	$users->delGroup($self->param('groupname'));
}

1;
