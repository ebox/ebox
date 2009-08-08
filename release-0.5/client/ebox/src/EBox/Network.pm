# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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

# Interfaces list which will be ignored
use constant IGNOREIFACES => qw(sit tun tap lo irda); 

use Net::IP;
use EBox::NetWrappers qw(:all);
use EBox::Validate qw(:all);
use EBox::Firewall;
use EBox::Config;
use EBox::Order;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataExists;
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
	my $self = $class->SUPER::_create(name => 'network', @_);
	bless($self, $class);
	return $self;
}

sub IPAddressExists
{
	my ($self, $ip) = @_;
	my @ifaces = @{$self->allIfaces()};

	foreach my $iface (@ifaces) {
		unless ($self->ifaceMethod($iface) eq 'static') {
			next;
		}
		if ($self->ifaceAddress($iface) eq $ip) {
			return 1;
		}
	}
	return undef;
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
	return iface_exists($name);
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

sub _ignoreIface($$){
	my ($self, $name) = @_;
	foreach my $ignore (IGNOREIFACES) {
		return 1 if  ($name =~ /$ignore.?/);
	}

	return undef;
}
# returns
#	- an array with the names of all real interfaces
sub ifaces
{
	my $self = shift;
	my @iflist = list_ifaces();
	my @array = ();
	foreach my $iface (@iflist) {
		next if $self->_ignoreIface($iface);
		push(@array, $iface);
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
		if (defined $hash->{'address'}) {
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
sub vifaceNames # (interface) 
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
			push @vifaces, @{$self->vifaceNames($_)};	
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
# 	- DataExists
# 		- If interface already exists
sub setViface # (real, virtual, address, netmask) 
{
	my ($self, $iface, $viface, $address, $netmask) = @_;
	
	unless ($self->ifaceMethod($iface) eq 'static') {
		throw EBox::Exceptions::Internal("Could not add virtual " .
				       "interface in non-static interface");
	}
	if ($self->_vifaceExists($iface, $viface)) {
		throw EBox::Exceptions::DataExists(
					'data' => __('Virtual interface name'),
					'value' => "$viface");
	}
	checkIPNetmask($address, $netmask, __('IP address'), __('Netmask'));
	checkVifaceName($iface, $viface, __('Virtual interface name'));

	if ($self->IPAddressExists($address)) {
		throw EBox::Exceptions::DataExists(
					'data' => __('IP address'),
					'value' => $address);
	}
	my $global = EBox::Global->getInstance();
	my @mods = @{$global->modNames};
	foreach (@mods) {
		my $mod = $global->modInstance($_);
		try {
			settextdomain($mod->{domain});
			$mod->vifaceAdded($iface, $viface, $address, $netmask);
		} otherwise {
			my $ex = shift;
			settextdomain('ebox');
			throw $ex;
		}
	}
	settextdomain('ebox');

	$self->set_string("interfaces/$iface/virtual/$viface/address",$address);
	$self->set_string("interfaces/$iface/virtual/$viface/netmask",$netmask);
	$self->set_bool("interfaces/$iface/changed", 'true');
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
		foreach (@{$self->vifaceNames($iface)}) {
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
sub removeViface # (real, virtual, force) 
{
	my ($self, $iface, $viface, $force) = @_;

	unless ($self->ifaceMethod($iface) eq 'static') {
		throw EBox::Exceptions::Internal("Could not remove virtual " .
            			      "interface from a non-static interface");
	}
	unless ($self->_vifaceExists($iface, $viface)) {
		return undef;
	}

	$self->_routersReachableIfChange("$iface:$viface");

	my $global = EBox::Global->getInstance();
	my @mods = @{$global->modNames};
	foreach (@mods) {
		my $mod = $global->modInstance($_);
		if ($mod->vifaceDelete($iface, $viface)) {
			if ($force) {
				$mod->freeViface($iface, $viface);
			} else {
				throw EBox::Exceptions::DataInUse();
			}
		}
	}

	$self->_cleanRedirectionsOnIface($iface . ":" . $viface);
	$self->delete_dir("interfaces/$iface/virtual/$viface");
	$self->set_bool("interfaces/$iface/changed", 'true');
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
sub setIfaceDHCP # (interface, external, force) 
{
	my ($self, $name, $ext, $force) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);	
	
	$self->_routersReachableIfChange($name);

	my $oldm = $self->ifaceMethod($name);

	if ($oldm ne 'dhcp') {
		my $global = EBox::Global->getInstance();
		my @mods = @{$global->modNames};
		foreach (@mods) {
			my $mod = $global->modInstance($_);
			if ($mod->ifaceMethodChanged($name, $oldm, 'dhcp')) {
				if ($force) {
					$mod->freeIface($name);
				} else {
					throw EBox::Exceptions::DataInUse();
				}
			}
		}
		$self->delete_dir("interfaces/$name");
	} else {
		my $oldm = $self->ifaceIsExternal($name);
		
		if ((defined($oldm) and defined($ext)) and ($oldm == $ext)) {
			return;
		}
	}

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
sub setIfaceStatic # (interface, address, netmask, external, force) 
{
	my ($self, $name, $address, $netmask, $ext, $force) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);	


	checkIPNetmask($address, $netmask, __('IP address'), __('Netmask'));

	my $oldm = $self->ifaceMethod($name);
	my $oldaddr = $self->ifaceAddress($name);
	my $oldmask = $self->ifaceNetmask($name);
	my $oldext = $self->ifaceIsExternal($name);

	if (($oldm eq 'static') and 
	    ($oldaddr eq $address) and
	    ($oldmask eq $netmask) and
	    ($oldext == $ext)) {
		return;
	}

	if ((!defined($oldaddr) or ($oldaddr ne $address)) and 
		$self->IPAddressExists($address)) {
		throw EBox::Exceptions::DataExists(
					'data' => __('IP address'),
					'value' => $address);
	}

	$self->_routersReachableIfChange($name, $address, $netmask);

	my $global = EBox::Global->getInstance();
	my @mods = @{$global->modNames};
	if ($oldm ne 'static') {
		foreach (@mods) {
			my $mod = $global->modInstance($_);
			if ($mod->ifaceMethodChanged($name, $oldm, 'static')) {
				if ($force) {
					$mod->freeIface($name);
				} else {
					throw EBox::Exceptions::DataInUse();
				}
			}
		}
	} else {
		foreach (@mods) {
			my $mod = $global->modInstance($_);
			if ($mod->staticIfaceAddressChanged($name, 
							$oldaddr, 
							$oldmask, 
							$address, 
							$netmask)) {
				if ($force) {
					$mod->freeIface($name);
				} else {
					throw EBox::Exceptions::DataInUse();
				}
			}
		}
	}

	$self->set_bool("interfaces/$name/external", $ext);
	$self->set_string("interfaces/$name/method", 'static');
	$self->set_string("interfaces/$name/address", $address);
	$self->set_string("interfaces/$name/netmask", $netmask);
	$self->set_bool("interfaces/$name/changed", 'true');
}

# Unset an interface
# arguments
# 	- the name of a network interface
sub unsetIface # (interface, force) 
{
	my ($self, $name, $force) = @_;
	unless ($self->ifaceExists($name)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	}
	unless ($self->ifaceOnConfig($name)) {
		return;
	}

	my $oldm = $self->ifaceMethod($name);

	$self->_routersReachableIfChange($name);

	if ($oldm ne 'notset') {
		my $global = EBox::Global->getInstance();
		my @mods = @{$global->modNames};
		foreach (@mods) {
			my $mod = $global->modInstance($_);
			if ($mod->ifaceMethodChanged($name, $oldm, 'notset')) {
				if ($force) {
					$mod->freeIface($name);
				} else {
					throw EBox::Exceptions::DataInUse();
				}
			}
		}
	}

	$self->_cleanRedirectionsOnIface($name);
	$self->delete_dir("interfaces/$name");
	$self->set_bool("interfaces/$name/changed", 'true');
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
		if (iface_is_up($name)) {
			return iface_netmask($name);
		}
	}
	return undef;
}

# arguments
# 	- the name of a network interface
# returns
# 	- For static interfaces: the configured Network of the interface.
#	- For dhcp interfaces:
#		- the current network if the interface is up
#		- undef if the interface is down
# 	- For not-yet-configured interfaces
# 		- undef
sub ifaceNetwork # (interface) 
{
	my ($self, $name) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	my $address;
	my $netmask;
		
	$address = $self->ifaceAddress($name);
	$netmask = $self->ifaceNetmask($name);
	if ($address) {
		return ip_network($address, $netmask);
	}
	return undef;
}

# arguments
# 	- the name of a network interface
# returns
# 	- For static interfaces: the broadcast Address of the interface.
#	- For dhcp interfaces:
#		- the current address if the interface is up
#		- undef if the interface is down
# 	- For not-yet-configured interfaces
# 		- undef
sub ifaceBroadcast # (interface) 
{
	my ($self, $name) = @_;
	$self->ifaceExists($name) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $name);
	my $address;
	my $netmask;
		
	$address = $self->ifaceAddress($name);
	$netmask = $self->ifaceNetmask($name);
	if ($address) {
		return ip_broadcast($address, $netmask);
	}
	return undef;
}

# returns
# 	- an array with the addresses of all nameservers
sub nameservers
{
	my $self = shift;
	my @array = ();
	foreach (1..2) {
		my $server = $self->get_string("nameserver" . $_);
		(defined($server) and ($server ne '')) or next;
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

# arguments
# 	- the IP address for the nameservers
sub setNameservers # (one, two) 
{
	my ($self, @dns) = @_;
	my @nameservers = ();
	my $i = 0;
	foreach (@dns) {
		$i++;
		($i < 3) or last;
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
	if (defined($self->gateway) and ($gw eq $self->gateway)) {
		return;
	}
	unless (length($gw) == 0) {
		checkIP($gw, __("IP address"));
		$self->_gwReachable($gw, __("Gateway"));
	}
	$self->set_string("gateway", $gw);
}

# returns
# 	- an array with hashes with keys network and gateway, where network
# 	is an IP block in CIDR format and gateway is an ip address.
sub routes
{
	my $self = shift;
	#my @routes = @{$order->list};
	#my @array = ();
	#foreach (@routes) {
	#	push(@array, $self->hash_from_dir($_));
	#}
	return $self->array_from_dir('routes');
	#return \@array;
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

	$ip = ip_network($ip, mask_from_bits($mask));
	if ($self->_alreadyInRoute($ip, $mask)) {
		throw EBox::Exceptions::DataExists('data' => 'network route',
						  'value' => "$ip/$mask");
	}

	my $id = $self->get_unique_id("r","routes");

	$self->set_string("routes/$id/ip", $ip);
	$self->set_int("routes/$id/mask", $mask);
	$self->set_string("routes/$id/gateway", $gw);
}

sub _markIfaceForRoute # (gateway)
{
	my ($self, $gw) = @_;

	foreach my $iface (@{$self->allIfaces()}) {
		my $host = $self->ifaceAddress($iface);
		my $mask = $self->ifaceNetmask($iface);
		my $meth = $self->ifaceMethod($iface);
		(defined($meth) eq 'static') or next;
		(defined($host) and defined($mask)) or next;
		if (isIPInNetwork($host,$mask,$gw)) {
			$self->_setChanged($iface);
		}
	}
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
		$self->_markIfaceForRoute($self->get_string("$_/gateway"));
		$self->delete_dir("$_");
		return;
	}
}

#returns true if the interface has been marked as changed
sub _hasChanged # (interface)
{
	my ($self, $iface) = @_;
	my $real = $iface;
	if ($self->vifaceExists($iface)) {
		($real) = $self->_viface2array($iface);
	} 
	return $self->get_bool("interfaces/$real/changed");
}

#returns true if the interface is empty (ready to be removed)
sub _isEmpty # (interface)
{
	my ($self, $ifc) = @_;
	if ($self->vifaceExists($ifc)) {
		my ($real, $vir) = $self->_viface2array($ifc);
		return (! defined($self->get_string(
				"interfaces/$real/virtual/$vir/address")));
	} else {
		return (! defined($self->get_string("interfaces/$ifc/method")));
	}
}

sub _removeIface # (interface)
{
	my ($self, $iface) = @_;
	if ($self->vifaceExists($iface)) {
		my ($real, $virtual) = $self->_viface2array($iface);
		return $self->delete_dir("interfaces/$real/virtual/$virtual");
	} else {
		return $self->delete_dir("interfaces/$iface");
	}
}

sub _unsetChanged # (interface)
{
	my ($self, $iface) = @_;
	if ($self->vifaceExists($iface)) {
		return;
	} else {
		return $self->unset("interfaces/$iface/changed");
	}
}

sub _setChanged # (interface)
{
	my ($self, $iface) = @_;
	if ($self->vifaceExists($iface)) {
		my ($real, $vir) = $self->_viface2array($iface);
		$self->set_bool("interfaces/$real/changed",'true');
	} else {
		$self->set_bool("interfaces/$iface/changed", 'true');
	}
}

sub _generateResolver
{
	my $self = shift;
	my $dnsfile = EBox::Config::tmp . "resolv.conf";
	open(RESOLVER, ">", $dnsfile) or
	throw EBox::Exceptions::Internal("Could not write on $dnsfile");
	my $dns = $self->nameservers();
	foreach (@{$dns}) {
		print RESOLVER "nameserver " . $_ . "\n";
	}
	close(RESOLVER);
	root("/bin/mv " . EBox::Config::tmp . "resolv.conf /etc/resolv.conf");
}

sub _generateInterfaces
{
	my $self = shift;
	my $file = EBox::Config::tmp . "/interfaces";
	my $iflist = $self->allIfaces();

	#writing /etc/network/interfaces
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
			print IFACES "\tbroadcast ". $self->ifaceBroadcast($_).
				"\n";
		}
	}
	close(IFACES);
}

sub _generateRoutes
{
	my $self = shift;
        my @routes = @{$self->routes};
        (@routes) or return;
	foreach (@routes) {
		my $net = $_->{ip} . "/" . $_->{mask};
		my $router = $_->{gateway};
		if (route_is_up($net, $router)) {
			root("/sbin/ip route del $net via $router");
		}
		root("/sbin/ip route add $net via $router");
	}
}

sub _regenConfig
{
	my $self = shift;
	my %opts = @_;
	my $restart = delete $opts{restart};

	my $gateway = $self->gateway;
	my $skipdns = undef;
	my $file = EBox::Config::tmp . "/interfaces";

	my $dhcpgw = $self->DHCPGateway();
	unless ($dhcpgw and ($dhcpgw ne '')) {
		try {
			root("/sbin/ip route del default");
		} catch EBox::Exceptions::Internal with {};
	}

	#bring down changed interfaces
	my $iflist = $self->allIfaces();
	foreach my $if (@{$iflist}) {
		if ($self->_hasChanged($if) or $restart) {
			try {
				root("/sbin/ip address flush label $if");
				root("/sbin/ip address flush label $if:*");
				root("/sbin/ifdown --force -i $file $if");
			} catch EBox::Exceptions::Internal with {};
			#remove if empty
			if ($self->_isEmpty($if)) {
				unless ($self->isReadOnly()) {
					$self->_removeIface($if);
				}
			}
		}
		if ($self->ifaceMethod($if) eq 'dhcp') {
			my @servers = @{$self->DHCPNameservers($if)};
			if (scalar(@servers) > 0) {
				$skipdns = 1;
			}
		}
	}

	$self->_generateInterfaces();

	unless ($skipdns) {
		# FIXME: there is a corner case when this won't be enough:
		# if the dhcp server serves some dns serves, those will be used,
		# but if it stops serving them at some point, the statically
		# configured ones will not be restored from the dhcp hook.
		#
		# If the server never gives dns servers, everything should work
		# Ok.
		$self->_generateResolver;
	}

	my @ifups = ();
	$iflist = $self->allIfaces();
	foreach (@{$iflist}) {
		if ($self->_hasChanged($_) or $restart) {
			push(@ifups, $_);
		}
	}
	foreach (@ifups) {
		root("/sbin/ifup --force -i $file $_");
		unless ($self->isReadOnly()) {
			$self->_unsetChanged($_);
		}
	}


	if ($gateway) {
		try {
			root("/sbin/ip route add default via $gateway");
		} catch EBox::Exceptions::Internal with {
			throw EBox::Exceptions::External("An error happened ".
			"trying to set the default gateway. Make sure the ".
			"gateway you specified is reachable.");
		};
	}

	$self->_generateRoutes();
}

sub stopService
{
	my $self = shift;

	my $file = EBox::Config::tmp . "/interfaces";
	my $iflist = $self->allIfaces();
	foreach my $if (@{$iflist}) {
		try {
			root("/sbin/ip address flush label $if");
			root("/sbin/ip address flush label $if:*");
			root("/sbin/ifdown --force -i $file $if");
		} catch EBox::Exceptions::Internal with {};
	}
}

#internal use functions
# XXX UNUSED FUNCTION
#sub _getInterfaces 
#{
	#my $iflist = Ifconfig('list');
	#return $iflist;
#}

# XXX UNUSED FUNCTION
#sub _getInterfacesArray 
#{
	#my $self = shift;
	#my $iflist = Ifconfig('list');
	#delete $iflist->{lo};
	#my @array;
	#my $i = 0;
	#while (my($key,$value) = each(%{$iflist})) {
		#my $entry;
		#$entry->{name} = $key;
		#($entry->{address}) = keys(%{$value->{inet}});
		#$entry->{netmask} = $value->{inet}->{$entry->{address}};
		#$entry->{status} = $value->{status};
		#$array[$i] = $entry;
		#$i++;
	#}
	#return \@array;
#}

sub _routersReachableIfChange # (interface, newaddress?, newmask?)
{
	my ($self, $iface, $newaddr, $newmask) = @_;

	my @routes = @{$self->routes()};
	my @ifaces = @{$self->allIfaces()};
	my @gws = ();
	foreach my $route (@routes) {
		push(@gws, $route->{gateway});
	}
	my $default = $self->gateway();
	if ($default and ($default ne '')) {
		push(@gws, $default);
	}

	foreach my $gw (@gws) {
		$gw .= "/32";
		my $reachable = undef;
		foreach my $if (@ifaces) {
			my $host; my $mask; my $meth;
			if ($iface eq $if) {
				$host = $newaddr;
				$mask = $newmask;
			} else {
				$meth = $self->ifaceMethod($if);
				($meth eq 'static') or next;
				$host = $self->ifaceAddress($if);
				$mask = $self->ifaceNetmask($if);
			}
			(defined($host) and defined($mask)) or next;
			if (isIPInNetwork($host, $mask, $gw)) {
				$reachable = 1;
			}
		}
		($reachable) or throw EBox::Exceptions::External(
			__('The requested operation will cause one of the '.
			   'configured routers to become unreachable. ' .
			   'Please remove it first if you really want to '.
			   'make this change.'));
	}
	return 1;
}

sub _gwReachable # (address, name?)
{
	my $self = shift;
	my $gw   = shift;
	my $name = shift;

	my $cidr_gw = "$gw/32";
	foreach (@{$self->allIfaces()}) {
		my $host = $self->ifaceAddress($_);
		my $mask = $self->ifaceNetmask($_);
		my $meth = $self->ifaceMethod($_);
		checkIPNetmask($gw, $mask) or next;
		($meth eq 'static') or next;
		(defined($host) and defined($mask)) or next;
		if (isIPInNetwork($host,$mask,$cidr_gw)) {
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
		my $rip = $self->get_string("$_/ip");
		my $rmask = $self->get_int("$_/mask");
		my $oip = new Net::IP("$ip/$mask");
		my $orip = new Net::IP("$rip/$rmask");
		if($oip->overlaps($orip)==$IP_IDENTICAL){
			return 1;
		}
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
	checkIPNetmask($ip, $mask,  __("IP address"), __('Netmask'));
	$self->st_set_string("dhcp/$iface/address", $ip);
	$self->st_set_string("dhcp/$iface/mask", $mask);
}

sub setDHCPGateway # (gateway) 
{
	my ($self, $gw) = @_;
	checkIP($gw, __("IP address"));
	$self->st_set_string("dhcp/gateway", $gw);
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

sub DHCPGateway
{
	my ($self) = @_;
	return $self->st_get_string("dhcp/gateway");
}

sub DHCPGatewayCleanUp
{
	my ($self) = @_;
	$self->st_unset("dhcp/gateway");
}

# parameters
# 	iface
sub DHCPAddress # (interface) 
{
	my ($self, $iface) = @_;
	$self->ifaceExists($iface) or
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
						     value => $iface);
	return $self->st_get_string("dhcp/$iface/address");
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
	foreach my $iface (@{$ifaces}) {
		my $status = __("down");
		my $section = new EBox::Summary::Section($iface);
		$item->add($section);

		if (iface_is_up($iface)) {
			$status = __("up");
		}
		$section->add(new EBox::Summary::Value (__("Status"), $status));

		my $ether = iface_mac_address($iface);
		if ($ether) {
			$section->add(new EBox::Summary::Value
				(__("MAC address"), $ether));
		}

		my @ips = iface_addresses($iface);
		foreach my $ip (@ips) {
			$section->add(new EBox::Summary::Value
				(__("IP address"), "$ip"));
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
	push(@array, "/bin/ip");
	push(@array, "/bin/mv " . EBox::Config::tmp . 
		"resolv.conf /etc/resolv.conf");
	push(@array, "/bin/cp /etc/network/interfaces " . EBox::Config::tmp .
		"interfaces");
	push(@array, "/bin/chown * " . EBox::Config::tmp .  "interfaces");
	return @array;
}

1;
