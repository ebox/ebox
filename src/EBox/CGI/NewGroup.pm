package EBox::CGI::UsersAndGroups::NewGroup;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'New group',
				      'template' => '/users/new_group.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

1;
