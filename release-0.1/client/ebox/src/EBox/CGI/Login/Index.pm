package EBox::CGI::Login::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';
use Apache;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => '',
				      'template' => '/login/index.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($){
	my $self = shift;
	my $r = Apache->request;
	my $envre= $r->prev->subprocess_env("LoginReason");
	my $reason;
	
	if ($r->prev->subprocess_env('AuthCookieReason') eq 'bad_credentials'){
		$reason = 'Password Incorrect';	
	}
	elsif ( defined $envre and $envre eq 'Expired'){
		$reason = 'For security reasons your session ' .
			  'has expired due to inactivity';
	}elsif (defined $envre and $envre eq 'Already'){
		$reason = 'You have been logged out because ' . 
			  'a new session has been opened';
	}
	my @array = ();
	push (@array, {'reason' => $reason});
	$self->{params} = \@array;
}

sub _top($) {
}

sub _loggedIn {
	return 1;
}

sub _menu {
	
	return;
}

1;
