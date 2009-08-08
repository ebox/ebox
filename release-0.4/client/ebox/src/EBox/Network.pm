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

package EBox::Network;

use strict;
use warnings;

use base 'EBox::GConfModule';

use Net::IPv4Addr qw(:all);
use Net::Ifconfig::Wrapper qw(:all);
use EBox::Firewall;
use EBox::Config;
use EBox::Order;
use EBox::Validate qw( :all );
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataInUse;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;
use Error qw(:try);
use EBox::Summary::Module;
use EBox::Summary::Value;
use EBox::Summary::Section;
use EBox::Sudo qw( :all );
use EBox::Gettext;
use File::Basename;

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'network');
	bless($self, $class);
	return $self;
}

sub ExternalIfaces
{
	my $self = shift;
	my @ifaces = @{$self->ifaces};
	my @array = ();
	foreach (@ifaces) {
		my $conf = $self->ifaceOnConfig($_);
		my $ext = $self->ifaceIsExternal($_);
		if ($conf and $ext) {
			push(@array, $_);
		}
	}
	return \@array;
}

sub InternalIfaces
{
	my $self = shift;
	my @ifaces = @{$self->ifaces};
	my @array = ();
	foreach (@ifaces) {
		my $conf = $self->ifaceOnConfig($_);
		my $ext = $self->ifaceIsExternal($_);
		if ($conf and (not $ext)) {
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
sub ifaceExists # (interface) 
{
	my ($self, $name) = @_;
	defined($name) or return undef;
	if ($self->vifaceExists($name)) {
		return 1;
	}
	my $iflist = Ifconfig('list');
	return exists($iflist->{$name});
}

sub ifaceIsExternal # (interface) 
{
	my ($self, $iface) = @_;
	defined($iface) or return undef;
	
	if ($self->vifaceExists($iface)) {
		my @aux = $self->_viface2array($iface);
		$iface = $aux[0];
	}
	return  $self->get_bool("interfaces/$iface/external");
}

# arguments
# 	- the name of a network interface
# returns
# 	- true, if the interface is in the configuration file
# 	- false, otherwise
sub ifaceOnConfig # (interface) 
{
	my ($self, $name) = @_;
	defined($name) or return undef;
	if ($self->vifaceExists($name)) {
		return 1;
	}
	return defined($self->get_string("interfaces/$name/method"));
}

# returns
#	- an array with the names of all real interfaces
sub ifaces
{
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

# arguments:
# 	- the name of a real interface
# returns:
# 	- an array ref holding hashes with "address" and "netmask" fields, the
# 	array may be empty (i.e. for a dhcp interface that did not get an
# 	address)
sub ifaceAddresses # (interface) 
{
	my ($self, $iface) = @_;
	my @array = ();

	if ($self->vifaceExists($iface)) {
		return \@array;
	}

	if ($self->ifaceMethod($iface) eq 'static') {
		my $addr = $self->get_string("interfaces/$iface/address");
		my $mask = $self->get_string("interfaces/$iface/netmask");
		push(@array, {address=>$addr, netmask=>$mask});
		my @virtual = $self->all_dirs("interfaces/$iface/virtual");
		foreach (@virtual) {
			my $name = basename($_);
			$addr = $self->get_string("$_/address");
			$mask = $self->get_string("$_/netmask");
			push(@array,   {address=>$addr,
					netmask=>$mask,
					name=>$name});
		}
	} elsif ($self->ifaceMethod($iface) eq 'dhcp') {
		my $addr = $self->DHCPAddress($iface);
		my $mask = $self->DHCPNetmask($iface);
		if ($addr && ($addr ne '')) {
			push(@array, {address=>$addr, netmask=>$mask});
		}
	}
	return \@array;
}

# Get  virtual interfaces from a real interface with their conf
# arguments
# 	- the name of a network interface
# returns
#	- an array with hashes with keys containing name, ip, and netmask. 
sub vifacesConf # (interface) 
{
	my $self = shift;
	my $iface = shift;
	defined($iface) or return;

	my @vifaces = $self->all_dirs("interfaces/$iface/virtual");
	my @array = ();	
	foreach (@vifaces) {
		my $hash = $self->hash_from_dir("$_");
		if (defined $hash->{'ip'}) {
			$hash->{'name'} = basename($_);
			push(@array, $hash);
		}
	}
	return \@array;
}

# arguments
# 	- the name of the real interface
# returns 
# 	- an array with the names of its virtual interaces.
# 	  Each name is a composed name like this: 
# 	  realinterface:virtualinterface (i.e: eth0:foo)
sub _vifaceNames # (interface) 
{
	my ($self, $iface) = @_;
	my @array;

	foreach (@{$self->vifacesConf($iface)}) {
		push @array, "$iface:" . $_->{'name'};
	}
	return \@array;
}
# returns
# 	- an array with the names of all (real and virtual) interfaces
sub allIfaces
{
	my $self = shift;
	my @array;
	my @vifaces;
	
	@array = @{$self->ifaces};
	foreach (@array) {
		if ($self->ifaceMethod($_) eq 'static') {
			push @vifaces, @{$self->_vifaceNames($_)};	
		}
	}
	push @array, @vifaces;
	@array = sort @array;
	return \@array;
}
# arguments
# 	- the name of the real network interface
# 	- the name of the virtual interface
# returns
# 	- true if exists
# 	- false if not
# throws
# 	- Internal
# 		- If real interface is not configured as static
sub _vifaceExists # (real, virtual)
{
	my ($self, $iface, $viface) = @_;
	
	unless ($self->ifaceMethod($iface) eq 'static') {
		throw EBox::Exceptions::Internal("Could not exist a virtual " .
			 		  "interface in non-static interface");
	}
	
	foreach (@{$self->vifacesConf($iface)}) {
		if ($_->{'name'} eq $viface) {
			return 1;
		}
	}
	return undef;
}

# split a virtual iface name in real interface and virtual interface
# arguments
# 	- the composed virtual iface name
# returns 
# 	- an array with the split name
sub _viface2array # (interface)
{
	my ($self, $name) = @_;
	my @array = $name =~ /(.*):(.*)/;
	return @array;
}

# arguments
# 	- the name of a virtual interface composed by
# 	  realinterface:virtualinterface 
# returns
# 	- true if it is a virtual interface and exists
# 	- false if not
sub vifaceExists # (interface)
{
	my ($self, $name) = @_;
	
	my ($iface, $viface) = $self->_viface2array($name);
	unless ($iface and $viface) {
		return undef;
	}
	return $self->_vifaceExists($iface, $viface);
}

# Configure a virtual  interface with ip and netmask
# arguments
# 	- the name of a real network interface
#	- the name of the virtual interface
#	- the IP address for the virtual interface
#	- the netmask
# throws
# 	- DataInUse
# 		- If interface already exists
sub setViface # (real, virtual, address, netmask) 
{
	my ($self, $iface, $viface, $address, $netmask) = @_;
	
	unless ($self->ifaceMethod($iface) eq 'static') {
		throw EBox::Exceptions::Internal("Could not add virtual " .
				       "interface in non-static interface");
	}
	if ($self->_vifaceExists($iface, $viface)) {
		throw EBox::Exceptions::DataInUse(
					'data' => __('Virtual interface name'),
					'value' => "$viface");
	}
	checkIP($address, __('IP address'));
	checkNetMask($netmask, __('Netmask'));
	checkVifaceName($iface, $viface, __('Virtual interface name'));
	
	$self->set_string("interfaces/$iface/virtual/$viface/address",$address);
	$self->set_string("interfaces/$iface/virtual/$viface/netmask",$netmask);
	$self->set_bool("interfaces/$iface/virtual/$viface/changed", 'true');
}

# Remove redirections using this interface in firewall
# arguments
# 	- the name of the network interface ( real or virtual)
sub _cleanRedirectionsOnIface # (interface) 
{
	my ($self, $iface) = @_;
	
	my $fw = EBox::Global->modInstance("firewall");
	if ($self->vifaceExists($iface)) {
		$fw->removePortRedirectionOnIface($iface);
		return 1;
	}
	unless ($self->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	}
	#Remove the real interface and all its virtual interfaces
	$fw->removePortRedirectionOnIface($iface);
	if ($self->ifaceMethod($iface) eq 'static') {
		foreach (@{$self->_vifaceNames($iface)}) {
			$fw->removePortRedirectionOnIface($_);	
		}
	}
	return 1;
}

# Remove a virtual interface
# arguments
# 	- the name of the real network interface
#	- the name of the virtual interface 
# returns
# 	- true if exists
# 	- false if not exists
sub removeViface # (real, virtual) 
{
	my ($self, $iface, $viface) = @_;

	unless ($self->ifaceMethod($iface) eq 'static') {
		throw EBox::Exceptions::Internal("Could not remove virtual " .
            			      "interface from a non-static interface");
	}
	unless ($self->_vifaceExists($iface, $viface)) {
		return undef;
	}
	$self->_cleanRedirectionsOnIface($iface . ":" . $viface);
	$self->delete_dir("interfaces/$iface/virtual/$viface");
	$self->set_bool("interfaces/$iface/virtual/$viface/changed", 'true');
	return 1;
}

# arguments
# 	- the composed name of a virtual interface
# returns
#	- IP if it exists
#	- false if not
sub vifaceAddress # (interface) 
{
	my ($self, $name) = @_;
	my $address;

	unless ($self->vifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	
	my ($iface, $viface) = $self->_viface2array($name);
	foreach (@{$self->vifacesConf($iface)}) {
		if ($_->{'name'} eq $viface) {
			return $_->{'address'};
		}
	}
	return undef;
}

# arguments
# 	- the composed name of a virtual interface
# returns
#	- IP if it exists
#	- false if not
sub vifaceNetmask # (interface) 
{
	my ($self, $name) = @_;
	my $address;

	unless ($self->vifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	
	my ($iface, $viface) = $self->_viface2array($name);
	foreach (@{$self->vifacesConf($iface)}) {
		if ($_->{'name'} eq $viface) {
			return $_->{'netmask'};
		}
	}
	return undef;
}

# arguments
# 	- the name of a network interface
# returns
# 	- dhcp|static|notset
#			dhcp -> the interface is configured via dhcp
#			static -> the interface is configured with a static ip
#			notset -> the interface exists but has not been
#				  configured yet
sub ifaceMethod # (interface) 
{
	my ($self, $name) = @_;
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	if ($self->vifaceExists($name)) {
		return 'static';
	}
	$self->ifaceOnConfig($name) or return 'notset';
	return $self->get_string("interfaces/$name/method");
}

# Configure an interface via DHCP
# arguments
# 	- the name of a network interface
sub setIfaceDHCP # (interface, external) 
{
	my ($self, $name, $ext) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);	
	$self->set_bool("interfaces/$name/external", $ext);
	$self->unset("interfaces/$name/address");
	$self->unset("interfaces/$name/netmask");
	$self->set_string("interfaces/$name/method", 'dhcp');
	$self->set_bool("interfaces/$name/changed", 'true');
}

# Configure an interface with a static ip address
# arguments
# 	- the name of a network interface
#	- the IP address for the interface
#	- the netmask
sub setIfaceStatic # (interface, address, netmask, external) 
{
	my ($self, $name, $address, $netmask, $ext) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);	
	checkIP($address, __('IP address'));
	checkNetMask($netmask, __('Netmask'));

	$self->set_bool("interfaces/$name/external", $ext);
	$self->set_string("interfaces/$name/method", 'static');
	$self->set_string("interfaces/$name/address", $address);
	$self->set_string("interfaces/$name/netmask", $netmask);
	$self->set_bool("interfaces/$name/changed", 'true');
}

# Unset an interface
# arguments
# 	- the name of a network interface
sub unsetIface # (interface) 
{
	my ($self, $name) = @_;
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	unless ($self->ifaceOnConfig($name)) {
		return;
	}
	$self->_cleanRedirectionsOnIface($name);
	$self->delete_dir("interfaces/$name");
	$self->set_bool("interfaces/$name/changed", 'true');
}

# arguments
# 	- the name of a network interface
# returns
# 	- true if the interface is up
# 	- false if the interface is down
sub ifaceIsUp # (interface) 
{
	my ($self, $name) = @_;
	if (! $self->ifaceExists($name)) {
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
sub ifaceAddress # (interface) 
{
	my ($self, $name) = @_;
	my $address;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	if ($self->vifaceExists($name)) {
		return $self->vifaceAddress($name);
	}
	if ($self->ifaceMethod($name) eq 'static') {
		return $self->get_string("interfaces/$name/address");
	} elsif ($self->ifaceMethod($name) eq 'dhcp') {
		return $self->DHCPAddress($name);
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
sub ifaceNetmask # (interface) 
{
	my ($self, $name) = @_;
	my $address;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);

	if ($self->vifaceExists($name)) {
		return $self->vifaceNetmask($name);
	}
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
sub nameservers
{
	my $self = shift;
	my @array = ();
	foreach (1..3) {
		my $server = $self->get_string("nameserver" . $_);
		($server) or next;
		push(@array, $server);
	}
	return \@array;
}

# returns
# 	- the primary nameserver's IP address
sub nameserverOne
{
	my $self = shift;
	return $self->get_string("nameserver1");
}

# returns
# 	- the secondary nameserver's IP address
sub nameserverTwo
{
	my $self = shift;
	return $self->get_string("nameserver2");
}

# returns
# 	- the tertiary nameserver's IP address
sub nameserverThree
{
	my $self = shift;
	return $self->get_string("nameserver3");
}

# arguments
# 	- the IP address for the nameservers
sub setNameservers # (one, two, three) 
{
	my ($self, @dns) = @_;
	my @nameservers = ();
	my $i = 0;
	foreach (@dns) {
		$i++;
		(length($_) == 0) or checkIP($_, __("IP address"));
		$self->set_string("nameserver$i", $_);
	}
}

# returns
# 	- the default gateway's ip address
# 	- undef if the gateway has not been set
sub gateway
{
	my $self = shift;
	return $self->get_string("gateway");
}

# sets the default gateway
# arguments
# 	- the default gateway's ip address
sub setGateway # (address) 
{
	my ($self, $gw) = @_;
	if ($gw eq $self->gateway) {
		return;
	}
	unless (length($gw) == 0) {
		checkIP($gw, __("IP address"));
		$self->_gwReachable($gw, __("Gateway"));
	}
	$self->set_string("gateway", $gw);
}

# ip mask
sub _routeNumber # (ip, mask) 
{
	my ($self, $ip, $mask) = @_;
	my @routes = $self->all_dirs("routes");
	foreach (@routes) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		return $self->get_int("$_/order");
	}
	return 0;
}

sub _routesOrder
{
	my $self = shift;
	$self->dir_exists("routes") or return undef;
	my $order = new EBox::Order($self, "routes");
	return $order;
}

sub _lastRoute
{
	my $self = shift;
	my $order = $self->_routesOrder;
	defined($order) or return 0;
	return $order->highest;
}

sub routeUp # (ip, mask) 
{
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

sub routeDown # (ip, mask) 
{
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
sub routes
{
	my $self = shift;
	my $order = $self->_routesOrder;
	defined($order) or return [];
	my @routes = @{$order->list};
	my @array = ();
	foreach (@routes) {
		push(@array, $self->hash_from_dir($_));
	}
	return \@array;
}

# arguments
# 	- the destination network (CIDR format)
#	- the gateway's ip address
sub addRoute # (ip, mask, gateway) 
{
	my ($self, $ip, $mask, $gw) = @_;

	checkCIDR("$ip/$mask", __("network address"));
	checkIP($gw, __("ip address"));
	$self->_gwReachable($gw, __("Gateway"));

	if ($self->_alreadyInRoute($ip, $mask)) {
		throw EBox::Exceptions::DataInUse('data' => 'network route',
						  'value' => "$ip/$mask");
	}

	my $id = $self->get_unique_id("r","routes");
	my $ordernum = $self->_lastRoute() + 1;

	$self->set_int("routes/$id/order", $ordernum);
	$self->set_string("routes/$id/ip", $ip);
	$self->set_int("routes/$id/mask", $mask);
	$self->set_string("routes/$id/gateway", $gw);
}

# arguments
# 	- the destination network whose route is to be deleted
sub delRoute # (ip, mask) 
{
	my ($self, $ip, $mask) = @_;

	my @routes = $self->all_dirs("routes");
	foreach (@routes) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		$self->delete_dir("$_");
		return;
	}
}

#returns true if the interface has been marked as changed
sub _hasChanged # (interface)
{
	my ($self, $iface) = @_;
#	if ($self->vifaceExists($iface)) {
#		my ($real, $vir) = $self->_viface2array($iface);
#		return $self->get_bool("interfaces/$real/virtual/$vir/changed");
#	} else {
#		return $self->get_bool("interfaces/$iface/changed");
#	}
	return 1;
}

#returns true if the interface is empty (ready to be removed)
sub _isEmpty # (interface)
{
	my ($self, $ifc) = @_;
	if ($self->vifaceExists($ifc)) {
		my ($real, $vir) = $self->_viface2array($ifc);
		return (! defined($self->get_string(
					"interfaces/$real/virtual/$vir/ip")));
	} else {
		return (! defined($self->get_string("interfaces/$ifc/method")));
	}
}

sub _removeIface # (interface)
{
	my ($self, $iface) = @_;
	if ($self->vifaceExists($iface)) {
		my ($real, $virtual) = $self->_viface2array($iface);
		return $self->delete_dir("interfaces/$real/virtual/$virtual/");
	} else {
		return $self->delete_dir("interfaces/$iface");
	}
}

sub _unsetChanged # (interface)
{
	my ($self, $iface) = @_;
	if ($self->vifaceExists($iface)) {
		my ($real, $vir) = $self->_viface2array($iface);
		return $self->unset("interfaces/$real/virtual/$vir/changed");
	} else {
		return $self->unset("interfaces/$iface/changed");
	}
}

sub _regenConfig
{
	my $self = shift;

	#bring down changed interfaces
	my $iflist = $self->allIfaces();
	foreach (@{$iflist}) {
		if ($self->_hasChanged($_)) {
			root("/sbin/ifdown $_");
			#remove if empty
			if ($self->_isEmpty($_)) {
				$self->_removeIface($_);
			}
		}
	}

	#writing /etc/network/interfaces
	my $file = EBox::Config::tmp . "/interfaces";
	open(IFACES, ">", $file) or
		throw EBox::Exceptions::Internal("Could not write on $file");
	print IFACES "auto lo";
	foreach (@{$iflist}) {
		if ($self->ifaceMethod($_) ne "notset") {
			print IFACES " " . $_;
		}
	}
	print IFACES "\niface lo inet loopback\n";
	foreach (@{$iflist}) {
		my $method = $self->ifaceMethod($_);
		if ($method eq 'dhcp') {
			print IFACES "iface " . $_ . " inet dhcp\n";
		} elsif ($method eq 'static') {
			print IFACES "iface " . $_ . " inet static\n";
			print IFACES "\taddress ". $self->ifaceAddress($_)."\n";
			print IFACES "\tnetmask ". $self->ifaceNetmask($_)."\n";
		}
	}
	close(IFACES);

	my $dnsfile = EBox::Config::tmp . "resolv.conf";
	open(RESOLVER, ">", $dnsfile) or
		throw EBox::Exceptions::Internal("Could not write on $dnsfile");
	my $dns = $self->nameservers();
	foreach (@{$dns}) {
		print RESOLVER "nameserver " . $_ . "\n";
	}
	close(RESOLVER);

	root("/bin/mv " . EBox::Config::tmp . "resolv.conf /etc/resolv.conf");

	foreach (@{$iflist}) {
		if ($self->_hasChanged($_)) {
			root("/sbin/ifup -i $file $_");
			#unset changed flag
			$self->_unsetChanged($_);
		}
	}

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
sub _getInterfaces 
{
	my $iflist = Ifconfig('list');
	return $iflist;
}

# XXX UNUSED FUNCTION
sub _getInterfacesArray 
{
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

sub _gwReachable # (address, name?)
{
	my $self = shift;
	my $gw   = shift;
	my $name = shift;

	$gw .= "/32";
	foreach (@{$self->allIfaces()}) {
		my $host = $self->ifaceAddress($_);
		my $mask = $self->ifaceNetmask($_);
		next unless ($host and $mask);
		my $ret;
		eval {
			$ret = ipv4_in_network($host, $mask, $gw);	
		};
		if ($ret) {
			return 1;
		}
	}

	if ($name) {
		   throw EBox::Exceptions::External(
			   __x("Gateway {gw} not reachable", gw => $gw));
        } else {
		return undef;
	}
}

sub _alreadyInRoute # (ip, mask) 
{
	my ( $self, $ip, $mask) = @_;
	my @routes = $self->all_dirs("routes");
	foreach (@routes) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		return 1;
	}
	return undef;
}

# parameters:
# 	iface
# 	address
# 	mask
sub setDHCPAddress # (interface, ip, mask) 
{
	my ($self, $iface, $ip, $mask) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	checkIP($ip, __("IP address"));
	checkNetMask($mask, __('Netmask'));
	$self->st_set_string("dhcp/$iface/address", $ip);
	$self->st_set_string("dhcp/$iface/mask", $mask);
}

# parameters
# 	iface
sub DHCPCleanUp # (interface) 
{
	my ($self, $iface) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	$self->st_delete_dir("dhcp/$iface");
}

# parameters
# 	iface
sub DHCPAddress # (interface) 
{
	my ($self, $iface) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	return $self->st_get_string("dhcp/$iface/ip");
}

# parameters
# 	iface
sub DHCPNetmask # (interface) 
{
	my ($self, $iface) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	return $self->st_get_string("dhcp/$iface/mask");
}

# parameters
# 	iface
# 	nameservers \@array
sub setDHCPNameservers # (interface, \@nameservers) 
{
	my ($self, $iface, $servers) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	foreach (@{$servers}) {
		checkIP($_, __("IP address"));
	}
	$self->st_set_list("dhcp/$iface/nameservers", "string", $servers);
}

# parameters
# 	iface
sub DHCPNameservers # (interface) 
{
	my ($self, $iface) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	return $self->st_get_list("dhcp/$iface/nameservers");
}

sub summary
{
	my $self = shift;
	my $item = new EBox::Summary::Module(__("Network interfaces"));
	my $ifaces = $self->ifaces;
	my $iflist = Ifconfig('list');
	foreach (@{$ifaces}) {
		my $status = __("down");
		my $section = new EBox::Summary::Section($_);
		$item->add($section);

		if ($iflist->{$_}->{status} == 1) {
			$status = __("up");
		}
		$section->add(new EBox::Summary::Value (__("Status"), $status));

		my $ether = $iflist->{$_}->{ether};
		if ($ether) {
			$section->add(new EBox::Summary::Value
				(__("MAC address"), $ether));
		}


		my @ips = keys(%{$iflist->{$_}->{inet}});
		my @masks = values(%{$iflist->{$_}->{inet}});
		while (1) {
			my $ip = shift @ips or last;
			my $mask = shift @masks or last;
			$section->add(new EBox::Summary::Value
				(__("IP address"), "$ip / $mask"));
		}
	}
	return $item;
}

sub rootCommands
{
	my $self = shift;
	my @array = ();
	push(@array, "/sbin/ifdown");
	push(@array, "/sbin/ifup");
	push(@array, "/sbin/ip");
	push(@array, "/bin/mv " . EBox::Config::tmp . 
		"resolv.conf /etc/resolv.conf");
	return @array;
}

1;
