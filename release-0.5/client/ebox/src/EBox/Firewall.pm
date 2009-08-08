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

package EBox::Firewall;

use strict;
use warnings;

use base 'EBox::GConfModule';

use EBox::Objects;
use EBox::Global;
use EBox::Validate qw( :all );
use EBox::Exceptions::InvalidData;
use EBox::Order;
use EBox::Gettext;

sub _create 
{
	my $class = shift;
	my $self =$class->SUPER::_create(name => 'firewall', @_);
	bless($self, $class);
	return $self;
}

## internal utility functions

sub _checkPolicy # (policy, name?) 
{
	my $i = shift;
	my $name = shift;
	if ($i eq "deny" || $i eq "allow" || $i eq "global") {
		return 1;
	}
	if (defined($name)) {
		throw EBox::Exceptions::InvalidData('data' => $name,
						    'value' => $i);
	} else {
		return 0;
	}
}

sub _checkAction # (action, name?) 
{
	my $i = shift;
	my $name = shift;
	if ($i eq "allow" || $i eq "deny") {
		return 1;
	}
	if (defined($name)) {
		throw EBox::Exceptions::InvalidData('data' => $name,
						    'value' => $i);
	} else {
		return 0;
	}
}

sub _purgeEmptyObject # (object) 
{
	my ($self, $object) = @_;

	if ($object eq '_global') {
		return;
	}
	
	my @array;
	@array = $self->all_dirs("objects/$object/rules");
	(scalar(@array) eq 0) or return;
	@array = $self->all_dirs("objects/$object/services");
	(scalar(@array) eq 0) or return;
	
	if ($self->ObjectPolicy($object) eq 'global') {
		$self->delete_dir("objects/$object");
	}
}


sub _purgeServiceObjects # (service) 
{
	my ($self, $service) = @_;
	foreach my $object(@{$self->ObjectNames}){
		foreach (@{$self->ObjectServices($object)}){
			if ( $_->{name} eq $service ){
				$self->removeObjectService($object, $service);
			}
		}
	}
}

# END internal utility functions

## api functions

sub _regenConfig
{
	my $self = shift;
	use EBox::Iptables;
	my $ipt = new EBox::Iptables;
	$ipt->start();
}

sub _stopService
{
	my $self = shift;
	use EBox::Iptables;
	my $ipt = new EBox::Iptables;
	$ipt->stop();
}

# arguments
# 	- the name of an Object
# returns
# 	- true: if this module currently uses the object
#	- false: if this module does not use the object
sub usesObject # (object) 
{
	my ($self, $object) = @_;
	defined($object) or return undef;
	($object ne "") or return undef;
	return $self->dir_exists("objects/$object");
}

sub freeObject # (object) 
{
	my ($self, $object) = @_;
	defined($object) or return;
	($object ne "") or return;
	$self->delete_dir("objects/$object");
}

sub ifaceMethodChanged # (iface, oldmethod, newmethod)
{
	my ($self, $iface, $oldmethod, $newmethod) = @_;

	($newmethod eq 'static') and return undef;
	($newmethod eq 'dhcp') and return undef;

	foreach my $red (@{$self->portRedirections()}) {
		($red->{iface} eq $iface) and return 1;
	}
	return undef;
}

sub vifaceDelete # (iface, viface)
{
	my ($self, $iface, $viface) = @_;

	foreach my $red (@{$self->portRedirections()}) {
		($red->{iface} eq "$iface:$viface") and return 1;
	}
	return undef;
}

# returns:
# 	- DROP|REJECT
sub denyAction
{
	my $self = shift;
	return $self->get_string("deny");
}

# arguments:
# 	- string: DROP|REJECT
sub setDenyAction # (action) 
{
	my ($self, $action) = @_;
	if ($action ne "DROP" && $action ne "REJECT") {
		throw EBox::Exceptions::InvalidData('data' => __('action'),
						    'value' => $action);
	} elsif ($action eq $self->denyAction()) {
		return;
	}
	$self->set_string("deny", $action);
}

sub portRedirections
{
	my $self = shift;
	return $self->array_from_dir("redirections");
}

# arguments:
# 	- string: protocol (tcp|udp)
#	- string: external port (1-65535)
#	- string: network interface
#	- string: destination address (valid IP address)
#	- string: destination port (1-65535)
sub addPortRedirection # (protocol, ext_port, interface, address, dest_port) 
{
	my ($self, $proto, $eport, $iface, $address, $dport) = @_;

	checkProtocol($proto, __("protocol"));
	checkIP($address, __("destination address"));
	checkPort($eport, __("external port"));
	checkPort($dport, __("destination port"));

	$self->availablePort($eport, $iface) or
		throw EBox::Exceptions::External(__x(
		"Port {port} is being used by a service or port redirection.", 
		port => $eport));

	my $id = $self->get_unique_id("r","redirections");

	$self->set_string("redirections/$id/protocol", $proto);
	$self->set_int("redirections/$id/eport", $eport);
	$self->set_string("redirections/$id/iface", $iface);
	$self->set_string("redirections/$id/ip", $address);
	$self->set_int("redirections/$id/dport", $dport);
}

# arguments:
# 	- string: protocol (tcp|udp)
#	- string: external port (1-65535)
#	- string: interface
sub removePortRedirection # (protocol, ext_port, interface) 
{
	my ($self, $proto, $eport, $iface) = @_;
	checkProtocol($proto, __("protocol"));
	checkPort($eport, __("external port"));

	my @reds = $self->all_dirs("redirections");
	foreach (@reds) {
		($self->get_string("$_/protocol") eq $proto) or next;
		($self->get_int("$_/eport") eq $eport) or next;
		($self->get_string("$_/iface") eq $iface) or next;
		$self->delete_dir($_);
		return 1;
	}
	return;
}

# arguments:
#	- string: interface
sub removePortRedirectionOnIface # (interface) 
{
	my ($self, $iface) = @_;
	my @reds = $self->all_dirs("redirections");
	foreach (@reds) {
		($self->get_string("$_/iface") eq $iface) or next;
		$self->delete_dir($_);
		return 1;
	}
	return;
}

sub services
{
	my $self = shift;
	return $self->array_from_dir("services");
}

# arguments:
# 	- string: the name of a service
# returns:
# 	- hash with service if exists
# 	- undef if service does not exists
sub service # (name) 
{
	my ($self, $name) = @_;
	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	my $service =  $self->hash_from_dir("services/$name");
	if (keys(%{$service})){
		return $service;
	} 
	return undef;
}

# arguments:
# 	- string: name of a service
# returns:
# 	- protocol for the service: tcp|udp
sub serviceProtocol # (service) 
{
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne "") or return undef;
	return $self->get_string("services/$name/protocol");
}

# arguments:
# 	- string: name of a service
# returns:
# 	- service port (1-65535)
sub servicePort # (service) 
{
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne "") or return undef;
	return $self->get_int("services/$name/port");
}

# arguments:
# 	- string: name of a service
# returns:
# 	- boolean
sub serviceIsInternal # (service) 
{
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne "") or return undef;
	return $self->get_bool("services/$name/internal");
}

# arguments:
# 	- string: port number
#	- string: interface (all internal ifaces if not passed)
# returns:
# 	- true  if free
# 	- false if already used
sub availablePort # (port, interface) 
{
	my ($self, $port, $iface) = @_;
	defined($port) or return undef;
	($port ne "") or return undef;
	my $global = EBox::Global->getInstance();
	my $network = $global->modInstance('network');

	# if it's an internal interface, check all services
	unless ($iface &&
	($network->ifaceIsExternal($iface) || $network->vifaceExists($iface))) {
		foreach (@{$self->services()}){
			if ($self->servicePort($_->{name}) == $port){
				return undef;
			}
		}
	}

	# check for port redirections on the interface, on all internal ifaces
	# if its
	my @ifaces = ();
	if ($iface) {
		push(@ifaces, $iface);
	} else {
		my $tmp = $network->InternalIfaces();
		@ifaces = @{$tmp};
	}
	my $redirs = $self->portRedirections();
	foreach my $ifc (@ifaces) {
		foreach my $red (@{$redirs}) {
			($red->{protocol} eq 'tcp') or next;
			($red->{iface} eq $ifc) or next;
			($red->{eport} eq $port) and return undef;
		}
	}

        my @modNames = @{$global->modNames};
        foreach my $name (@modNames) {
                my $mod = $global->modInstance($name);
                if ($mod->usesPort('tcp', $port, $iface)) {
                        return undef;
                }
        }
	return 1;
}

# arguments:
# 	- string: name of a service, must not already exist
# 	- string: protocol (tcp|udp)
# 	- string: port (1-65535)
# 	- boolean: internal?
sub addService # (name, protocol, port, internal?) 
{
	my ($self, $name, $proto, $port, $internal) = @_;

	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	checkProtocol($proto, __("protocol"));
	checkPort($port, __("port"));

	$self->dir_exists("services/$name") and
		throw EBox::Exceptions::DataExists('data' =>__('service'),
						  'value' => $name);

	my @servs = @{$self->all_dirs_base("services")};
	foreach (@servs) {
		($self->get_string("services/$_/protocol") eq $proto) or next;
		($self->get_int("services/$_/port") eq $port) or next;
		throw EBox::Exceptions::DataExists('data' =>'local port',
						  'value' => $port);
	}
	$self->set_string("services/$name/protocol", $proto);
	$self->set_string("services/$name/name", $name);
	$self->set_int("services/$name/port", $port);
	$self->set_bool("services/$name/internal", $internal);
}

# arguments:
# 	- string: name of the service
# returns:
# 	- true when removing the service
# 	- false if there's nothing to remove
sub removeService # (service) 
{
	my ($self, $name) = @_;
	my $i = 0;
	
	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	if ($self->service($name)){
		$self->delete_dir("services/$name");
		$self->removeLocalRedirects($name);
		$self->_purgeServiceObjects($name);
		return 1;
	} else { 
		return undef;	
	}
} 

# arguments:
# 	- string: name of the service, must exist
# 	- string: protocol (tcp|udp)
# 	- string: port (1-65535)
# 	- boolean: internal
sub changeService # (service, protocol, port, internal?) 
{
	my ($self, $name, $proto, $port, $internal) = @_;

	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	checkProtocol($proto, __("protocol"));
	checkPort($port, __("port"));

	my @servs = @{$self->all_dirs_base("services")};
	foreach (@servs) {
		($_ ne $name) or next;
		($self->get_string("services/$_/protocol") eq $proto) or next;
		($self->get_int("services/$_/port") eq $port) or next;
		throw EBox::Exceptions::DataExists('data' =>'local port',
						  'value' => $port);
	}

	$self->set_string("services/$name/protocol", $proto);
	$self->set_string("services/$name/name", $name);
	$self->set_int("services/$name/port", $port);
	$self->set_bool("services/$name/internal", $internal);
}

sub localRedirects
{
	my $self = shift;
	return $self->array_from_dir("localredirects");
}

# arguments
# 	- string: name of the service
# 	- string: port to redirect from 
sub addLocalRedirect # (service, port) 
{
	my ($self, $name, $port) = @_;
	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	checkPort($port, __("port"));

	my $protocol = $self->serviceProtocol($name);
	($protocol && $protocol ne "") or 
		throw EBox::Exceptions::Internal("Unknown service: $name");

	my @redirects = $self->all_dirs("localredirects");
	foreach (@redirects) {
		my $tmpsrv = $self->get_string("$_/service");
		if ($tmpsrv eq $name) {
			if ($self->get_int("$_/port") eq $port) {
				return;
			} else {
				next;
			}
		}
		my $tmpproto = $self->serviceProtocol($tmpsrv);
		($tmpproto eq $protocol) or next;
		if ($self->get_int("$_/port") eq $port) {
			throw EBox::Exceptions::Internal
			("Port $port already redirected to service $tmpsrv");
		}
	}

	my $id = $self->get_unique_id("r","localredirects");

	$self->set_string("localredirects/$id/service", $name);
	$self->set_int("localredirects/$id/port", $port);
}

# arguments
# 	- string: name of the service
sub removeLocalRedirects # (service) 
{
	my ($self, $name) = @_;
	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));

	my @redirects = $self->all_dirs("localredirects");
	foreach (@redirects) {
		if ($self->get_string("$_/service") eq $name) {
			$self->delete_dir("$_");
		}
	}
}

# arguments
# 	- string: name of the service
sub removeLocalRedirect # (service, port) 
{
	my ($self, $name, $port) = @_;
	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));

	my @redirects = $self->all_dirs("localredirects");
	foreach (@redirects) {
		($self->get_string("$_/service") eq $name) or next;
		($self->get_int("$_/port") eq $port) or next;
		$self->delete_dir("$_");
	}
}

# arguments:
# 	- string: name of the object
# returns:
# 	- string, the default policy for the object (global|deny|allow)
sub ObjectPolicy # (object) 
{
	my ($self, $name) = @_;

	if ($name ne '_global') {
		checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	}

	$self->dir_exists("objects/$name") or return 'global';
	return $self->get_string("objects/$name/policy");
}

sub _createObject # (object) 
{
	my ($self, $object) = @_;
	my $objects = EBox::Global->modInstance('objects');

	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}

	$self->dir_exists("objects/$object") and return;
	$self->set_string("objects/$object/policy", 'global');
}

# arguments:
# 	- string: name of the object
# 	- string: the default policy for the object (global|deny|allow)
sub setObjectPolicy # (object, policy) 
{
	my ($self, $object, $policy) = @_;
	my $objects = EBox::Global->modInstance('objects');

	_checkPolicy($policy, __("policy"));
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}
	if ($policy eq $self->ObjectPolicy($object)) {
		return;
	}
	$self->set_string("objects/$object/policy", $policy);
	$self->_purgeEmptyObject($object);
}

# arguments:
# 	- string: name of the object
# 	- string: name of the rule
sub removeObjectRule # (object, rule_id)
{
	my ($self, $object, $rule) = @_;

	$self->ObjectRuleExists($object, $rule) or return;
	$self->delete_dir("objects/$object/rules/$rule");
	$self->_purgeEmptyObject($object);
	return 1;
}

# arguments:
# 	- string: name of the object
# 	- string: name of a rule
# returns
# 	true if the rule exists
# 	false otherwise
sub ObjectRuleExists # (object, rule_id) 
{
	my ($self, $object, $rule) = @_;
	(defined($object) && $object ne "") or return undef;
	(defined($rule) && $rule ne "") or return undef;
	return $self->dir_exists("objects/$object/rules/$rule");
}

# arguments:
# 	- string: name of the object
# 	- string: name of the rule
# 	- string: action (deny|allow)
# 	- string: protocol (tcp|udp)
#	- string: port (1-65535)
#	- string: address (cidr address or empty) [optional]
#	- string: mask (1-32 or empty) [optional]
#	- string: active (yes|no)
sub changeObjectRule #(object, rule, action, protocol, port, addr, mask, active) 
{
	my ($self, $object, $rule, $action, $protocol, $port, $addr, $mask,
		   $active) = @_;

	_checkAction($action, __("policy"));

	if (defined($protocol) && $protocol ne "") {
		checkProtocol($protocol, __("protocol"));
	} elsif (defined($port) && $port ne "") {
		throw EBox::Exceptions::External(__('Port cannot be set if no'.
						' protocol is selected.'));
	}

	if (defined($port) && $port ne "") {
		checkPort($port, __("port"));
	}
	if (defined($addr) && $addr ne "") {
		checkCIDR("$addr/$mask", __("address"));
	}

	$self->ObjectRuleExists($object, $rule) or return;

	$self->set_string("objects/$object/rules/$rule/name", $rule);
	$self->set_string("objects/$object/rules/$rule/action", $action);
	$self->set_bool("objects/$object/rules/$rule/active", $active);

	if (defined($protocol) && $protocol ne "") {
		$self->set_string("objects/$object/rules/$rule/protocol", 
					$protocol);
	} else {
		$self->unset("objects/$object/rules/$rule/protocol");
	}

	if (defined($port) && $port ne "") {
		$self->set_int("objects/$object/rules/$rule/port", $port);
	} else {
		$self->unset("objects/$object/rules/$rule/port");
	}

	if (defined($addr) && $addr ne "") {
		$self->set_string("objects/$object/rules/$rule/address", $addr);
	}
	if (defined($mask) && $mask ne "") {
		$self->set_int("objects/$object/rules/$rule/mask", $mask);
	}
}

sub OutputRules
{
	my $self = shift;
	return $self->array_from_dir("rules/output");
}

# arguments:
# 	- string: protocol (tcp|udp)
# 	- string: protocol (tcp|udp)
sub removeOutputRule # (protocol, port)
{
	my ($self, $protocol, $port) = @_;

	checkProtocol($protocol, __("protocol"));
	checkPort($port, __("port"));

	my @rules = $self->all_dirs("rules/output");
	foreach (@rules) {
		($self->get_string("$_/protocol") eq $protocol) or next;
		($self->get_int("$_/port") eq $port) or next;
		$self->delete_dir($_);
		return 1;
	}
	return;
}

# arguments:
# 	- string: protocol (tcp|udp)
# 	- string: port
sub addOutputRule # (protocol, port) 
{
	my ($self, $protocol, $port) = @_;

	checkProtocol($protocol, __("protocol"));
	checkPort($port, __("port"));

	$self->removeOutputRule($protocol, $port);

	my $id = $self->get_unique_id("r","rules/output");

	$self->set_string("rules/output/$id/protocol", $protocol);
	$self->set_int("rules/output/$id/port", $port);
}

# arguments:
# 	- string: name of the object
# 	- string: action (deny|allow)
# 	- string: protocol (tcp|udp) [optional]
#	- string: port (1-65535) [optional]
#	- string: address (cidr address or empty) [optional]
#	- string: mask (1-32 or empty) [optional]
sub addObjectRule # (object, action, protocol, port, address, mask) 
{
	my ($self, $object, $action, $protocol, $port, $addr, $mask) = @_;

	_checkAction($action, __("policy"));

	if (defined($protocol) && $protocol ne "") {
		checkProtocol($protocol, __("protocol"));
	} elsif (defined($port) && $port ne "") {
		throw EBox::Exceptions::External(__('Port cannot be set if no'.
						' protocol is selected.'));
	}

	if (defined($port) && $port ne "") {
		checkPort($port, __("port"));
	}

	if (defined($addr) && $addr ne "") {
		checkCIDR("$addr/$mask", __("address"));
	}

	my $objects = EBox::Global->modInstance('objects');
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}

	$self->dir_exists("objects/$object") or $self->_createObject($object);

	my $id = $self->get_unique_id("x","objects/$object/rules");

	my $order = $self->_lastObjectRule($object) + 1;
	$self->set_string("objects/$object/rules/$id/name", $id);
	$self->set_string("objects/$object/rules/$id/action", $action);
	$self->set_bool("objects/$object/rules/$id/active", 1);
	$self->set_int("objects/$object/rules/$id/order", $order);
	if (defined($protocol) && $protocol ne "") {
		$self->set_string("objects/$object/rules/$id/protocol", 
				$protocol);
	}
	if (defined($port) && $port ne "") {
		$self->set_int("objects/$object/rules/$id/port", $port);
	}
	if (defined($addr) && $addr ne "") {
		$self->set_string("objects/$object/rules/$id/address", $addr);
	}
	if (defined($mask) && $mask ne "") {
		$self->set_int("objects/$object/rules/$id/mask", $mask);
	}
}

# arguments:
# 	- string: name of the object
# 	- string: name of the service
sub removeObjectService # (object, service) 
{
	my ($self, $object, $service) = @_;

	my $objects = EBox::Global->modInstance('objects');
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}
	checkName($service) or throw EBox::Exceptions::Internal(
			"Name $service is invalid");

	$self->delete_dir("objects/$object/services/$service");
	$self->_purgeEmptyObject($object);
	return 1;
}

# arguments:
# 	- string: name of the object
# 	- string: name of the service
# 	- string: policy (allow|deny)
sub setObjectService # (object, service, policy) 
{
	my ($self, $object, $srv, $policy) = @_;

	_checkAction($policy, __("policy"));
	my $objects = EBox::Global->modInstance('objects');
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}

	$self->dir_exists("services/$srv") or return;
	$self->dir_exists("objects/$object") or $self->_createObject($object);
	$self->set_string("objects/$object/services/$srv/policy", $policy);
	$self->set_string("objects/$object/services/$srv/name", $srv);
}

## fields: name policy
#  dirs: rule servicepol

# arguments:
# 	- string: name of the object
sub Object # (name) 
{
	my ($self, $name) = @_;
	my $hash = {};
	$hash->{policy} = $self->ObjectPolicy($name);
	$hash->{name} = $name;
	$hash->{rule} = $self->array_from_dir("objects/$name/rules");
	$hash->{servicepol} = $self->array_from_dir("objects/$name/services");
	return $hash;
}

sub _objectRuleNumber # (object, rule) 
{
	my ($self, $object, $rule) = @_;
	return $self->get_int("objects/$object/rules/$rule/order");
}

sub _objectRulesOrder # (object) 
{
	my ($self, $name) = @_;
	$self->dir_exists("objects/$name/rules") or return undef;
	return new EBox::Order($self, "objects/$name/rules");
}

sub ObjectRuleUp # (object, rule) 
{
	my ($self, $object, $rule) = @_;
	my $order = $self->_objectRulesOrder($object);
	defined($order) or return;
	my $num = $self->_objectRuleNumber($object, $rule);
	if ($num == 0) {
		return;
	}

	my $prev = $order->prevn($num);
	$order->swap($num, $prev);
}

sub ObjectRuleDown # (object, rule) 
{
	my ($self, $object, $rule) = @_;
	my $order = $self->_objectRulesOrder($object);
	defined($order) or return;
	my $num = $self->_objectRuleNumber($object, $rule);
	if ($num == 0) {
		return;
	}

	my $nextn = $order->nextn($num);
	$order->swap($num, $nextn);
}

# arguments:
# 	- string: name of the object
sub ObjectRules # (object) 
{
	my ($self, $name) = @_;
	my $order = $self->_objectRulesOrder($name);
	defined($order) or return undef;
	my @rules = @{$order->list};
	my @array = ();
	foreach (@rules) {
		push(@array, $self->hash_from_dir($_));
	}
	return \@array;
}

sub _lastObjectRule # (object) 
{
	my ($self, $name) = @_;
	my $order = $self->_objectRulesOrder($name);
	defined($order) or return 0;
	return $order->highest;
}

# arguments:
# 	- string: name of the object
sub ObjectServices # (object) 
{
	my ($self, $name) = @_;
	return $self->array_from_dir("objects/$name/services");
}

sub ObjectNames
{
	my $self = shift;
	return $self->all_dirs_base("objects");
}

sub rootCommands
{
	my $self = shift;
	my @array = ();
	push(@array, '/sbin/iptables');
	push(@array, '/sbin/sysctl -q -w net.ipv4.ip_forward*');
	return @array;
}

1;
