package EBox::CGI::Network::Route;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Network/Index";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	$self->_requireParam('ip', __('network address'));
	$self->_requireParam('mask', __('network mask'));
	
	if (defined($self->param('del'))) {
		$net->delRoute($self->param("ip"), $self->param("mask"));
	} elsif (defined($self->param('add'))) {
		$self->_requireParam('gateway', __('gateway address'));
		$net->addRoute( $self->param('ip'),
				$self->param('mask'),
				$self->param('gateway'));
	} elsif (defined($self->param('up'))) {
		$net->routeUp($self->param("ip"), $self->param("mask"));
	} elsif (defined($self->param('down'))) {
		$net->routeDown($self->param("ip"), $self->param("mask"));
	}
}

1;
