package EBox::CGI::UsersAndGroups::NewUser;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'New user',
				      'template' => '/users/new_user.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

1;
