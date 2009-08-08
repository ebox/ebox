=head1 NAME

EBox::Network - EBOX Network handling module

=head1 DESCRIPTION

This module is used to configure the network interfaces, DNS servers and
static routes

=cut

package EBox::Network;

use strict;
use warnings;

use base 'EBox::XMLModule';

use Net::IPv4Addr qw(:all);
use Net::Ifconfig::Wrapper qw(:all);
use EBox::Config;
use EBox::Order;
use EBox::Validate;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataInUse;
use EBox::Exceptions::Internal;
use EBox::Exceptions::Unknown;
use Error qw(:try);
use EBox::Summary::Module;
use EBox::Summary::Value;
use EBox::Summary::Section;
use EBox::Sudo qw( :all );

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

=head1 METHODS

=cut

sub _create {
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'network');
	bless($self, $class);
	return $self;
}

sub getExternalIfaces($) {
	my $self = shift;
	my $ifaces = $self->adoc->{interface};
	defined($ifaces) or return ();
	my @array = ();
	foreach (@{$ifaces}) {
		if ($_->{external} eq 'yes') {
			push(@array, $_->{name});
		}
	}
	return \@array;
}

sub getInternalIfaces($) {
	my $self = shift;
	my $ifaces = $self->adoc->{interface};
	defined($ifaces) or return ();
	my @array = ();
	foreach (@{$ifaces}) {
		if ($_->{external} eq 'no') {
			push(@array, $_->{name});
		}
	}
	return \@array;
}

# arguments
# 	- the name of a network interface
# returns
# 	- true, if the interface exists
# 	- false, otherwise
sub ifaceExists($$) {
	my ($self, $name) = @_;
	defined($name) or return undef;
	my $iflist = Ifconfig('list');
	return exists($iflist->{$name});
}

sub ifaceIsExternal($$) {
	my ($self, $iface) = @_;
	$self->ifaceOnConfig($iface) or return 'no';
	return $self->hdoc->{interface}->{$iface}->{external};
}

# arguments
# 	- the name of a network interface
# returns
# 	- true, if the interface is in the configuration file
# 	- false, otherwise
sub ifaceOnConfig($$) {
	my ($self, $name) = @_;
	return defined($self->hdoc->{interface}->{$name});
}

# Removes an interface from the configuration.
# arguments
# 	- the name of a network interface
sub delIface($$) {
	my ($self, $name) = @_;
	if(! $self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
			value => $name);
	}
	delete($self->hdoc->{interface}->{$name});
	$self->writeHashFile;
}

# returns
#	- an array with the names of all interfaces
sub ifaces($) {
	my $self = shift;
	my $iflist = Ifconfig('list');
	delete $iflist->{lo};
	my @array;
	my $i = 0;
	while (my($key,$value) = each(%{$iflist})) {
		$array[$i] = $key;
		$i++;
	}
	return \@array;
}

# arguments
# 	- the name of a network interface
# returns
# 	- dhcp|static|notset
#			dhcp -> the interface is configured via dhcp
#			static -> the interface is configured with a static ip
#			notset -> the interface exists but has not been
#				  configured yet
sub ifaceMethod($$) {
	my ($self, $name) = @_;
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	$self->ifaceOnConfig($name) or return 'notset';
	return $self->hdoc->{interface}->{$name}->{method};
}

# Configure an interface via DHCP
# arguments
# 	- the name of a network interface
sub setIfaceDHCP($$$) {
	my ($self, $name, $ext) = @_;
	my $external = 'no';
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
			value => $name);	
	}
	if ($ext) {
		$external = 'yes';
	}
	if (ifaceMethod($self, $name) eq 'static') {
		delete($self->hdoc->{interface}->{$name}->{address});
		delete($self->hdoc->{interface}->{$name}->{netmask});
	}
	$self->hdoc->{interface}->{$name}->{method} = 'dhcp';
	$self->hdoc->{interface}->{$name}->{external} = $external;
	$self->writeHashFile;
}

# Configure an interface with a static ip address
# arguments
# 	- the name of a network interface
#	- the IP address for the interface
#	- the netmask
sub setIfaceStatic($$$$$) {
	my ($self, $name, $address, $netmask, $ext) = @_;
	my $external = 'no';
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
			value => $name);	
	}
	unless (EBox::Validate::checkIP($address)) {
		throw EBox::Exceptions::InvalidData(data => __('IP Address'),
			value => $address);	
	}
	if ($ext) {
		$external = 'yes';
	}
	$self->hdoc->{interface}->{$name}->{method} = 'static';
	$self->hdoc->{interface}->{$name}->{address} = $address;
	$self->hdoc->{interface}->{$name}->{netmask} = $netmask;
	$self->hdoc->{interface}->{$name}->{external} = $external;
	$self->writeHashFile;
}

# Unset an interface
# arguments
# 	- the name of a network interface
sub unsetIface($$) {
	my ($self, $name) = @_;
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	delete($self->hdoc->{interface}->{$name});
	if ((scalar keys(%{$self->hdoc->{interface}})) == 0){
		delete($self->hdoc->{interface});
	}
	$self->writeHashFile;
}

# arguments
# 	- the name of a network interface
# returns
# 	- true if the interface is up
# 	- false if the interface is down
sub ifaceIsUp($$) {
	my ($self, $name) = @_;
	if(! $self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
			value => $name);
	}
	my $iflist = Ifconfig('list');
	return $iflist->{$name}->{status};
}

# arguments
# 	- the name of a network interface
# returns
# 	- For static interfaces: the configured IP Address of the interface.
#	- For dhcp interfaces:
#		- the current address if the interface is up
#		- undef if the interface is down
# 	- For not-yet-configured interfaces
# 		- undef
sub ifaceAddress($$) {
	my ($self, $name) = @_;
	my $address;
	if(! $self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
			value => $name);
	}
	if($self->ifaceMethod($name) eq 'static') {
		return $self->hdoc->{interface}->{$name}->{address};
	} elsif ($self->ifaceMethod($name) eq 'dhcp') {
		if($self->ifaceIsUp($name)){
			my $iflist = Ifconfig('list');
			($address) = keys(%{$iflist->{$name}->{inet}});
			return $address;
		}else{
			return undef;
		}
	} else {
		return undef;
	}
}

# arguments
# 	- the name of a network interface
# returns
# 	- For static interfaces: the configured netmask of the interface.
#	- For dhcp interfaces:
#		- the current netmask if the interface is up
#		- undef if the interface is down
#	- For unconfigured interfaces:
#		- undef
sub ifaceNetmask($$) {
	my ($self, $name) = @_;
	my $address;
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
			value => $name);
	}
	if ($self->ifaceMethod($name) eq 'static') {
		return $self->hdoc->{interface}->{$name}->{netmask};
	} elsif ($self->ifaceMethod($name) eq 'dhcp') {
		if ($self->ifaceIsUp($name)) {
			my $iflist = Ifconfig('list');
			($address) = keys(%{$iflist->{$name}->{inet}});
			return $iflist->{$name}->{inet}->{$address};
		} else {
			return undef;
		}
	} else {
		return undef;
	}
}

# returns
# 	- an array with the addresses of all nameservers
sub nameservers($) {
	my $self = shift;
	return $self->hdoc->{nameservers}[0]->{address};
}

# returns
# 	- the primary nameserver's IP address
sub nameserverOne($) {
	my $self = shift;
	return @{$self->hdoc->{nameservers}[0]->{address}}[0];
}

# returns
# 	- the secondary nameserver's IP address
sub nameserverTwo($) {
	my $self = shift;
	return @{$self->hdoc->{nameservers}[0]->{address}}[1];
}

# returns
# 	- the tertiary nameserver's IP address
sub nameserverThree($) {
	my $self = shift;
	return @{$self->hdoc->{nameservers}[0]->{address}}[2];
}

# arguments
# 	- the IP address for the nameservers
sub setNameservers($$$$) {
	my ($self, @dns) = @_;
	my @nameservers = ();
	foreach(@dns){
		unless ((EBox::Validate::checkIP($_) or (length($_) == 0))) {
			throw EBox::Exceptions::InvalidData(
				data => 'IP address', value => $_);
		}
		if (length($_) > 0) {
			push @nameservers, $_;
		}
	}
	$self->hdoc->{nameservers}[0]->{address} = \@nameservers;
	$self->writeHashFile;
}

# arguments
# 	- the IP address for the primary nameserver
sub setNameserverOne($$) {
	my ($self, $dns) = @_;
	unless ((EBox::Validate::checkIP($dns) or (length($dns) == 0))) {
		throw EBox::Exceptions::InvalidData(
			data => 'IP address', value => $dns);
	}
	$self->hdoc->{nameservers}[0]->{address}[0] = $dns;
	$self->writeHashFile;
}

# arguments
# 	- the IP address for the secondary nameserver
sub setNameserverTwo($$) {
	my ($self, $dns) = @_;
	unless ((EBox::Validate::checkIP($dns) or (length($dns) == 0))) {
		throw EBox::Exceptions::InvalidData(
			data => 'IP address', value => $dns);
	}
	$self->hdoc->{nameservers}[0]->{address}[1] = $dns;
	$self->writeHashFile;
}

# arguments
# 	- the IP address for the tertiary nameserver
sub setNameserverThree($$) {
	my ($self, $dns) = @_;
	unless ((EBox::Validate::checkIP($dns) or (length($dns) == 0))) {
		throw EBox::Exceptions::InvalidData(
			data => 'IP address', value => $dns);
	}
	$self->hdoc->{nameservers}[0]->{address}[2] = $dns;
	$self->writeHashFile;
}

# returns
# 	- the default gateway's ip address
# 	- undef if the gateway has not been set
sub gateway($) {
	my $self = shift;
	return $self->hdoc->{routes}[0]->{default}[0]->{gateway};
}

# sets the default gateway
# arguments
# 	- the default gateway's ip address
sub setGateway($$) {
	my ($self, $gw) = @_;
	#TODO: check if gateway is reachable ...
	$self->hdoc->{routes}[0]->{default}[0]->{gateway} = $gw;
	
	$self->writeHashFile;
}

# ip mask
sub _routeNumber($$$) {
	my ($self, $ip, $mask) = @_;
	my $routes = $self->routes();
	defined($routes) or return 0;
	foreach (@{$routes}) {
		if ($_->{ip} eq $ip && $_->{mask} eq $mask) {
			return $_->{order};
		}
	}
	return 0;
}

sub _routesOrder($) {
	my $self = shift;
	my $routes = $self->adoc->{routes}[0]->{net};
	defined($routes) or return undef;
	my $order = new EBox::Order($routes, 'order');
	return $order;
}

sub _lastRoute($) {
	my $self = shift;
	my $order = $self->_routesOrder;
	defined($order) or return 0;
	return $order->highest;
}

sub routeUp($$$) {
	my ($self, $ip, $mask)  = @_;
	my $order = $self->_routesOrder();
	defined($order) or return;
	my $num = $self->_routeNumber($ip, $mask);
	if ($num == 0) {
		return;
	}

	my $prev = $order->prevn($num);
	$order->swap($num, $prev);
	$self->writeArrayFile;
}

sub routeDown($$$) {
	my ($self, $ip, $mask)  = @_;
	my $order = $self->_routesOrder();
	defined($order) or return;
	my $num = $self->_routeNumber($ip, $mask);
	if ($num == 0) {
		return;
	}

	my $next = $order->nextn($num);
	$order->swap($num, $next);
	$self->writeArrayFile;
}

# returns
# 	- an array with hashes with keys network and gateway, where network
# 	is an IP block in CIDR format and gateway is an ip address.
sub routes($) {
	my $self = shift;
	my $order = $self->_routesOrder;
	defined($order) or return ();
	return $order->list;
}

# arguments
# 	- the destination network (CIDR format)
#	- the gateway's ip address
sub addRoute($$$$) {
	my ($self, $ip, $mask, $gw) = @_;
	unless (EBox::Validate::checkCIDR("$ip/$mask")) {
		throw EBox::Exceptions::InvalidData
			('data' => "network address", 'value' => "$ip/$mask");
	}

	#TODO: comprobar que los gw son alcanzables mediante alguna interfaz
	unless (EBox::Validate::checkIP($gw)) {
		throw EBox::Exceptions::InvalidData
			('data' => "ip address", 'value' => $gw);
	}

	if ($self->_alreadyInRoute($ip, $mask)) {
		throw EBox::Exceptions::DataInUse('data' => 'network route',
						  'value' => "$ip/$mask");
	}

	my $ordernum = $self->_lastRoute() + 1;
	if (defined($self->hdoc->{routes}[0]->{net})) {
		my $array = $self->hdoc->{routes}[0]->{net};
		push (@$array, { 'ip' => $ip,
				 'mask' => $mask,
				 'order' => $ordernum,
				 'gateway' => $gw } );
	} else {
		my $array = ();
		push (@$array, { 'ip' => $ip,
				 'mask' => $mask,
				 'order' => $ordernum,
				 'gateway' => $gw } );
		$self->hdoc->{routes}[0]->{net} = $array;
	}
	$self->writeHashFile();
}

# arguments
# 	- the destination network whose route is to be deleted
sub delRoute($$$) {
	my ($self, $ip, $mask) = @_;

	my @routes = @{$self->hdoc->{routes}[0]->{net}};

	my $index;
	# FIXME !!!!!!!!!!!!!!!!!!!!!!!!!!! FIXME FIXME FIXME
	for($index = 0;
		($ip ne $routes[$index]->{ip} &&
		 $mask ne $routes[$index]->{mask}) and
		($index <= $#routes);
		$index++){};
	if ($index != ($#routes+1)) {
		splice (@routes,$index,1);
		@{$self->hdoc->{routes}[0]->{net}} = @routes;
	} else {
		throw EBox::Exceptions::InvalidData(data => "network address",
						    value => "$ip/$mask");
	}
	$self->writeHashFile;
}

sub _regenConfig($){
	my $self = shift;

	#writing /etc/network/interfaces
	my $iflist = $self->ifaces();

	my $file = EBox::Config::tmp . "/interfaces";
	open(INTERFACES, ">", $file) or
		throw EBox::Exceptions::Internal("Could not write on $file");
	print INTERFACES "auto lo";
	foreach (@{$iflist}) {
		if ($self->ifaceMethod($_) ne "notset") {
			print INTERFACES " " . $_;
		}
	}
	print INTERFACES "\niface lo inet loopback\n";
	foreach (@{$iflist}) {
		my $method = $self->ifaceMethod($_);
		if ($method eq 'dhcp') {
			print INTERFACES "iface " . $_ . " inet dhcp\n";
		} elsif ($method eq 'static') {
			print INTERFACES "iface " . $_ . " inet static\n";
			print INTERFACES "\taddress " . $self->ifaceAddress($_) . "\n";
			print INTERFACES "\tnetmask " . $self->ifaceNetmask($_) . "\n";
		}
	}
	close(INTERFACES);

	my $dnsfile = EBox::Config::tmp . "/resolv.conf";
	open(RESOLVER, ">", $dnsfile) or
		throw EBox::Exceptions::Internal("Could not write on $dnsfile");
	my $dns = $self->nameservers();
	foreach (@{$dns}) {
		print RESOLVER "nameserver " . $_ . "\n";
	}
	close(RESOLVER);

	root("/bin/mv " . EBox::Config::tmp . "/resolv.conf /etc/resolv.conf");

	root("/sbin/ifdown -i $file -a");
	root("/sbin/ifup -i $file -a");

	my $gateway = $self->gateway;

	if ($gateway) {
		try {
			root("/sbin/ip route del default");
		} catch EBox::Exceptions::Internal with {};
		try {
			root("/sbin/ip route add default via $gateway");
		} catch EBox::Exceptions::Internal with {
			throw EBox::Exceptions::Internal("An error happened ".
			"trying to set the default gateway. Make sure the ".
			"gateway you specified is reachable.");
		};
	}
	my @routes = @{$self->routes};
	(@routes) or return;
	foreach (@routes) {
		my $net = $_->{ip} . "/" . $_->{mask};
		my $router = $_->{gateway};
		root("/sbin/ip route add $net via $router");
	}
}

#internal use functions
# XXX UNUSED FUNCTION
sub _getInterfaces {
	my $iflist = Ifconfig('list');
	return $iflist;
}

# XXX UNUSED FUNCTION
sub _getInterfacesArray {
	my $self = shift;
	my $iflist = Ifconfig('list');
	delete $iflist->{lo};
	my @array;
	my $i = 0;
	while (my($key,$value) = each(%{$iflist})) {
		my $entry;
		$entry->{name} = $key;
		($entry->{address}) = keys(%{$value->{inet}});
		$entry->{netmask} = $value->{inet}->{$entry->{address}};
		$entry->{status} = $value->{status};
		$array[$i] = $entry;
		$i++;
	}
	return \@array;
}

sub _alreadyInRoute($$$) {
	my ( $self, $iparg, $maskarg) = @_;
	my $nodeset = $self->xpdoc->find('/network/routes/net');

	foreach my $node ($nodeset->get_nodelist) {
		my $ip = $node->getAttribute('ip');
		my $mask = $node->getAttribute('mask');
		if (($iparg eq $ip) && ($maskarg eq $mask)) {
			return 1;
		}
	}
	return undef;
}

sub summary($) {
	my $self = shift;
	my $item = new EBox::Summary::Module(__("Network"));
	my $section = new EBox::Summary::Section(__("Interfaces"));
	$item->add($section);
	my $ifaces = $self->ifaces;
	my $iflist = Ifconfig('list');
	foreach (@{$ifaces}) {
		my $status;
		if ($self->ifaceIsUp($_)) {
			($status) = keys(%{$iflist->{$_}->{inet}});
		} else {
			$status = "down";
		}
		defined($status) or next;
		$section->add(new EBox::Summary::Value($_, $status));
	}
	return $item;
}

1;
