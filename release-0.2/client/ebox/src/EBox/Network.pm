# Copyright (C) 2004  Warp Netwoks S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=head1 NAME

EBox::Network - EBOX Network handling module

=head1 DESCRIPTION

This module is used to configure the network interfaces, DNS servers and
static routes

=cut

package EBox::Network;

use strict;
use warnings;

use base 'EBox::GConfModule';

use Net::IPv4Addr qw(:all);
use Net::Ifconfig::Wrapper qw(:all);
use EBox::Config;
use EBox::Order;
use EBox::Validate qw( :all );
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
	my @ifaces = $self->all_dirs_base("interfaces");
	my @array = ();
	foreach (@ifaces) {
		if ($self->get_bool("interfaces/$_/external")) {
			push(@array, $_);
		}
	}
	return \@array;
}

sub getInternalIfaces($) {
	my $self = shift;
	my @ifaces = $self->all_dirs_base("interfaces");
	my @array = ();
	foreach (@ifaces) {
		unless ($self->get_bool("interfaces/$_/external")) {
			push(@array, $_);
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
	defined($iface) or return 'no';
	if ($self->get_bool("interfaces/$iface/external")) {
		return 'yes';
	}
	return 'no';
}

# arguments
# 	- the name of a network interface
# returns
# 	- true, if the interface is in the configuration file
# 	- false, otherwise
sub ifaceOnConfig($$) {
	my ($self, $name) = @_;
	defined($name) or return undef;
	return $self->dir_exists("interfaces/$name");
}

# Removes an interface from the configuration.
# arguments
# 	- the name of a network interface
sub delIface($$) {
	my ($self, $name) = @_;
	defined($name) or return;
	($name ne "") or return;
	$self->delete_dir("interfaces/$name");
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
	return $self->get_string("interfaces/$name/method");
}

# Configure an interface via DHCP
# arguments
# 	- the name of a network interface
sub setIfaceDHCP($$$) {
	my ($self, $name, $ext) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);	
	$self->set_bool("interfaces/$name/external", $ext);
	$self->unset("interfaces/$name/address");
	$self->unset("interfaces/$name/netmask");
	$self->set_string("interfaces/$name/method", 'dhcp');
}

# Configure an interface with a static ip address
# arguments
# 	- the name of a network interface
#	- the IP address for the interface
#	- the netmask
sub setIfaceStatic($$$$$) {
	my ($self, $name, $address, $netmask, $ext) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);	
	checkIP($address, __('IP Address'));
	# FIXME check mask

	$self->set_bool("interfaces/$name/external", $ext);
	$self->set_string("interfaces/$name/method", 'static');
	$self->set_string("interfaces/$name/address", $address);
	$self->set_string("interfaces/$name/netmask", $netmask);
}

# Unset an interface
# arguments
# 	- the name of a network interface
sub unsetIface($$) {
	my ($self, $name) = @_;
	unless ($self->ifaceOnConfig($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	$self->delete_dir("interfaces/$name");
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
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);

	if ($self->ifaceMethod($name) eq 'static') {
		return $self->get_string("interfaces/$name/address");
	} elsif ($self->ifaceMethod($name) eq 'dhcp') {
		if ($self->ifaceIsUp($name)) {
			my $iflist = Ifconfig('list');
			($address) = keys(%{$iflist->{$name}->{inet}});
			return $address;
		} 
	}
	return undef;
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
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);

	if ($self->ifaceMethod($name) eq 'static') {
		return $self->get_string("interfaces/$name/netmask");
	} elsif ($self->ifaceMethod($name) eq 'dhcp') {
		if ($self->ifaceIsUp($name)) {
			# FIXME isn't this wrong??
			my $iflist = Ifconfig('list');
			($address) = keys(%{$iflist->{$name}->{inet}});
			return $iflist->{$name}->{inet}->{$address};
		}
	}
	return undef;
}

# returns
# 	- an array with the addresses of all nameservers
sub nameservers($) {
	my $self = shift;
	my @array = ();
	foreach (1..3){
		my $server = $self->get_string("nameserver" . $_);
		($server) or next;
		push(@array, $server);
	}
	return \@array;
}

# returns
# 	- the primary nameserver's IP address
sub nameserverOne($) {
	my $self = shift;
	return $self->get_string("nameserver1");
}

# returns
# 	- the secondary nameserver's IP address
sub nameserverTwo($) {
	my $self = shift;
	return $self->get_string("nameserver2");
}

# returns
# 	- the tertiary nameserver's IP address
sub nameserverThree($) {
	my $self = shift;
	return $self->get_string("nameserver3");
}

# arguments
# 	- the IP address for the nameservers
sub setNameservers($$$$) {
	my ($self, @dns) = @_;
	my @nameservers = ();
	my $i = 0;
	foreach(@dns){
		$i++;
		(length($_) == 0) and next;
		checkIP($_, __("IP address"));
		$self->set_string("nameserver$i", $_);
	}
}

# arguments
# 	- the IP address for the primary nameserver
sub setNameserverOne($$) {
	my ($self, $dns) = @_;
	(length($dns) == 0) or checkIP($dns, __("IP addresss"));
	$self->set_string("nameserver1", $dns);
}

# arguments
# 	- the IP address for the secondary nameserver
sub setNameserverTwo($$) {
	my ($self, $dns) = @_;
	(length($dns) == 0) or checkIP($dns, __("IP addresss"));
	$self->set_string("nameserver2", $dns);
}

# arguments
# 	- the IP address for the tertiary nameserver
sub setNameserverThree($$) {
	my ($self, $dns) = @_;
	(length($dns) == 0) or checkIP($dns, __("IP addresss"));
	$self->set_string("nameserver3", $dns);
}

# returns
# 	- the default gateway's ip address
# 	- undef if the gateway has not been set
sub gateway($) {
	my $self = shift;
	return $self->get_string("gateway");
}

# sets the default gateway
# arguments
# 	- the default gateway's ip address
sub setGateway($$) {
	my ($self, $gw) = @_;
	checkIP($gw, "IP address");
	# FIXME check if gateway is reachable ...
	$self->set_string("gateway", $gw);
}

# ip mask
sub _routeNumber($$$) {
	my ($self, $ip, $mask) = @_;
	my @routes = $self->all_dirs("routes");
	foreach (@routes) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		return $self->get_int("$_/order");
	}
	return 0;
}

sub _routesOrder($) {
	my $self = shift;
	$self->dir_exists("routes") or return undef;
	my $order = new EBox::Order($self, "routes");
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
}

# returns
# 	- an array with hashes with keys network and gateway, where network
# 	is an IP block in CIDR format and gateway is an ip address.
sub routes($) {
	my $self = shift;
	my $order = $self->_routesOrder;
	defined($order) or return [];
	my @routes = $order->list;
	my @array = ();
	foreach (@routes) {
		push(@array, $self->hash_from_dir($_));
	}
	return \@array;
}

# arguments
# 	- the destination network (CIDR format)
#	- the gateway's ip address
sub addRoute($$$$) {
	my ($self, $ip, $mask, $gw) = @_;

	checkCIDR("$ip/$mask", __("network address"));
	# FIXME comprobar que los gw son alcanzables mediante alguna interfaz
	checkIP($gw, __("ip address"));

	if ($self->_alreadyInRoute($ip, $mask)) {
		throw EBox::Exceptions::DataInUse('data' => 'network route',
						  'value' => "$ip/$mask");
	}

	my $id = "r" . int(rand(10000));
	while ($self->dir_exists("routes/$id")) {
		$id = "r" . int(rand(10000));
	}
	my $ordernum = $self->_lastRoute() + 1;

	$self->set_int("routes/$id/order", $ordernum);
	$self->set_string("routes/$id/ip", $ip);
	$self->set_int("routes/$id/mask", $mask);
	$self->set_string("routes/$id/gateway", $gw);
}

# arguments
# 	- the destination network whose route is to be deleted
sub delRoute($$$) {
	my ($self, $ip, $mask) = @_;

	my @routes = $self->all_dirs("routes");
	foreach (@routes) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		$self->delete_dir("$_");
		return;
	}
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
	my ( $self, $ip, $mask) = @_;
	my @routes = $self->all_dirs("routes");
	foreach (@routes) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		return 1;
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
