package EBox::CGI::Network::Iface;

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

	$self->_requireParam("method", __("method"));
	$self->_requireParam("ifname", __("network interface"));

	my $iface = $self->param("ifname");
	my $method = $self->param("method");
	my $external = undef;
	if (defined($self->param('external'))) {
		$external = 1;
	}

	if ($method eq 'static') {
		$self->_requireParam("if_address", __("ip address"));
		$self->_requireParam("if_netmask", __("netmask"));
		my $address = $self->param("if_address");
		my $netmask = $self->param("if_netmask");
		$net->setIfaceStatic($iface, $address, $netmask, $external);
	} elsif ($method eq 'dhcp') {
		$net->setIfaceDHCP($iface, $external);
	} elsif ($method eq 'notset') {
		$net->unsetIface($iface);
	}
}

1;
