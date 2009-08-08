package EBox::CGI::Logout::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';
use Apache;
use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Logout'),
				      'template' => '/logout/index.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	if ($global->unsaved) {
		my @array = ();
		push(@array, {'unsaved' => 'yes'});
		$self->{params} = \@array;
	}
}

sub _loggedIn {
	return 1;
}


1;
