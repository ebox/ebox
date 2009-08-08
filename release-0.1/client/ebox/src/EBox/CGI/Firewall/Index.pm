package EBox::CGI::Firewall::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Firewall;
use EBox::Objects;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Firewall'),
				      'template' => '/firewall/index.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');
	my $objects = EBox::Global->modInstance('objects');
	my $net = EBox::Global->modInstance('network');

	my $redirections = $firewall->portRedirections;
	my $objectlist = $objects->getObjectsArray();
	my $aux = $net->ifaces;
	my @ifaces = ();
	foreach(@{$aux}) {
		push(@ifaces, {'name' => $_});
	}

	foreach (@{$objectlist}) {
		delete($_->{member});
	}

	my @array = ();

	if (defined($redirections)) {
		push(@array, {'redirections' => $redirections});
	}

	push(@array, {'ifaces' => \@ifaces});
	push(@array, {'deny' => $firewall->denyAction});
	if ($objectlist && length(@{$objectlist}) > 0) {
		push(@array, {'objects' => $objectlist});
	}
	$self->{params} = \@array;
}

1;
