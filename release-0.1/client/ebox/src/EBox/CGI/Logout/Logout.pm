package EBox::CGI::Logout::Logout;

use strict;
use warnings;

use mod_perl;

use base 'EBox::CGI::Base';

use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Logout',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;

	my $r = Apache->request;
	my $auth_type = $r->auth_type;

	# Delete the cookie
	$auth_type->logout($r);

	$self->{redirect} = "/Login/Login";

	my $global = EBox::Global->modInstance('global');
	$global->revokeAllModules;
}

1;
