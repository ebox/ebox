package EBox::CGI::UsersAndGroups::ModGroup;

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

	$users->modifyGroup($self->param('groupname'),
				{ name => $self->param('oldgroupname'),
				  gid => $self->param('oldgid'),
				  desc => $self->param('oldgroupdescription')}
			);
}

1;
