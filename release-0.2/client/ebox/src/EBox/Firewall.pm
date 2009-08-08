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

package EBox::Firewall;

use strict;
use warnings;

use base 'EBox::GConfModule';

use EBox::Objects;
use EBox::Global;
use EBox::Validate qw( :all );
use Data::Dumper;
use EBox::Exceptions::InvalidData;
use EBox::Order;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub _create {
	my $class = shift;
	my $self =$class->SUPER::_create(name => 'firewall');
	bless($self, $class);
	return $self;
}

## internal utility functions

sub _checkPolicy {
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

sub _checkAction {
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

sub _purgeEmptyObject($$) {
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

# END internal utility functions

## api functions

sub _regenConfig($) {
	my $self = shift;
	use EBox::Iptables;
	my $ipt = new EBox::Iptables;
	$ipt->start();
}

sub stopService($) {
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
sub usesObject($$) {
	my ($self, $object) = @_;
	defined($object) or return undef;
	($object ne "") or return undef;
	return $self->dir_exists("objects/$object");
}

sub freeObject($$) {
	my ($self, $object) = @_;
	defined($object) or return;
	($object ne "") or return;
	$self->delete_dir("objects/$object");
}

# returns:
# 	- DROP|REJECT
sub denyAction($) {
	my $self = shift;
	return $self->get_string("deny");
}

# arguments:
# 	- string: DROP|REJECT
sub setDenyAction($$) {
	my ($self, $action) = @_;
	if ($action ne "DROP" && $action ne "REJECT") {
		throw EBox::Exceptions::InvalidData('data' => __('action'),
						    'value' => $action);
	} elsif ($action eq $self->denyAction()) {
		return;
	}
	$self->set_string("deny", $action);
}

sub portRedirections($) {
	my $self = shift;
	return $self->array_from_dir("redirections");
}

# arguments:
# 	- string: protocol (tcp|udp)
#	- string: external port (1-65535)
#	- string: network interface
#	- string: destination address (valid IP address)
#	- string: destination port (1-65535)
sub addPortRedirection($$$$$) {
	my ($self, $proto, $eport, $iface, $address, $dport) = @_;

	checkProtocol($proto, __("protocol"));
	checkIP($address, __("destination address"));
	checkPort($eport, __("external port"));
	checkPort($dport, __("destination port"));

	my $id = "r" . int(rand(10000));
	while ($self->dir_exists("redirections/$id")) {
		$id = "r" . int(rand(10000));
	}
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
sub removePortRedirection($$$$) {
	my ($self, $proto, $eport, $iface) = @_;
	checkProtocol($proto, __("protocol"));
	checkPort($eport, __("external port"));

	my @reds = $self->all_dirs("redirections");
	foreach (@reds) {
		($self->get_string("$_/protocol") eq $proto) or next;
		($self->get_int("$_/eport") eq $eport) or next;
		($self->get_string("$_/iface") eq $iface) or next;
		$self->delete_dir($_);
		return;
	}
}

sub services($) {
	my $self = shift;
	return $self->array_from_dir("services");
}

# arguments:
# 	- string: the name of a service
sub service($$) {
	my ($self, $name) = @_;
	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	return $self->hash_from_dir("services/$name");
}

# arguments:
# 	- string: name of a service
# returns:
# 	- protocol for the service: tcp|udp
sub serviceProtocol($$) {
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne "") or return undef;
	return $self->get_string("services/$name/protocol");
}

# arguments:
# 	- string: name of a service
# returns:
# 	- service port (1-65535)
sub servicePort($$) {
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne "") or return undef;
	return $self->get_int("services/$name/port");
}

# arguments:
# 	- string: name of a service, must not already exist
# 	- string: protocol (tcp|udp)
# 	- string: port (1-65535)
sub addService($$$$) {
	my ($self, $name, $proto, $port) = @_;

	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	checkProtocol($proto, __("protocol"));
	checkPort($port, __("port"));

	$self->dir_exists("services/$name") and
		throw EBox::Exceptions::DataInUse('data' =>'service',
						  'value' => $name);

	my @servs = $self->all_dirs_base("services");
	foreach (@servs) {
		($self->get_string("services/$_/protocol") eq $proto) or next;
		($self->get_int("services/$_/port") eq $port) or next;
		throw EBox::Exceptions::DataInUse('data' =>'local port',
						  'value' => $port);
	}
	$self->set_string("services/$name/protocol", $proto);
	$self->set_string("services/$name/name", $name);
	$self->set_int("services/$name/port", $port);
}

# arguments:
# 	- string: name of the service
sub removeService($$) {
	my ($self, $name) = @_;
	my $i = 0;

	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	$self->delete_dir("services/$name");
	# FIXME remove the service from the Objects section too
} 

# arguments:
# 	- string: name of the service, must exist
# 	- string: protocol (tcp|udp)
# 	- string: port (1-65535)
sub changeService($$$$) {
	my ($self, $name, $proto, $port) = @_;

	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	checkProtocol($proto, __("protocol"));
	checkPort($port, __("port"));

	$self->removeService($name);
	$self->addService($name, $proto, $port);
}

# arguments:
# 	- string: name of the service, must exist
# 	- string: dnat port (1-65535)
sub setServiceDNat($$$) {
	my ($self, $name, $port) = @_;

	checkName($name) or throw EBox::Exceptions::Internal(
				__x("Name '{name}' is invalid", name => $name));
	checkPort($port, __("port"));

	$self->dir_exists("services/$name") or
		throw EBox::Exceptions::DataNotFound('data' => __("service"),
						     'value' => $name);

	$self->set_int("services/$name/dnatport", $port);
}

# arguments:
# 	- string: name of the service, must exist
sub unsetServiceDNat($$) {
	my ($self, $name) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	$self->dir_exists("services/$name") or
		throw EBox::Exceptions::DataNotFound('data' => __("service"),
						     'value' => $name);
	
	$self->unset("services/$name/dnatport");
}

# arguments:
# 	- string: name of the object
# returns:
# 	- string, the default policy for the object (global|deny|allow)
sub ObjectPolicy($$) {
	my ($self, $name) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	$self->dir_exists("objects/$name") or return 'global';
	return $self->get_string("objects/$name/policy");
}

sub _createObject($$) {
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
sub setObjectPolicy($$$) {
	my ($self, $object, $policy) = @_;
	my $objects = EBox::Global->modInstance('objects');

	_checkPolicy($policy, __("policy"));
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}
	$self->set_string("objects/$object/policy", 'global');
	$self->_purgeEmptyObject($object);
}

# arguments:
# 	- string: name of the object
# 	- string: name of the rule
sub removeObjectRule {
	my ($self, $object, $rule) = @_;

	$self->ObjectRuleExists($object, $rule) or return;
	$self->delete_dir("objects/$object/rules/$rule");
	$self->_purgeEmptyObject($object);
}

# arguments:
# 	- string: name of the object
# 	- string: name of a rule
# returns
# 	true if the rule exists
# 	false otherwise
sub ObjectRuleExists($$$) {
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
sub changeObjectRule($$$$$$$$) {
	my ($self, $object, $rule, $action, $protocol, $port, $addr, $mask,
		   $active) = @_;

	_checkAction($action, __("policy"));
	checkProtocol($protocol, __("protocol"));
	checkPort($port, __("port"));
	if (defined($addr) && $addr ne "") {
		checkCIDR("$addr/$mask") or
			throw EBox::Exceptions::DataMissing(
						'data' => __("address"),
						'value' => "$addr/$mask");
	}

	$self->ObjectRuleExists($object, $rule) or return;

	$self->set_string("objects/$object/rules/$rule/name", $rule);
	$self->set_string("objects/$object/rules/$rule/action", $action);
	$self->set_string("objects/$object/rules/$rule/protocol", $protocol);
	$self->set_int("objects/$object/rules/$rule/port", $port);
	$self->set_bool("objects/$object/rules/$rule/active", $active);
	if (defined($addr) && $addr ne "") {
		$self->set_string("objects/$object/$rule/address", $addr);
	}
	if (defined($mask) && $mask ne "") {
		$self->set_int("objects/$object/$rule/mask", $mask);
	}
}

sub OutputRules($) {
	my $self = shift;
	return $self->array_from_dir("rules/output");
}

# arguments:
# 	- string: protocol (tcp|udp)
# 	- string: protocol (tcp|udp)
sub removeOutputRule {
	my ($self, $protocol, $port) = @_;

	checkProtocol($protocol, __("protocol"));
	checkPort($port, __("port"));

	my @rules = $self->all_dirs("rules/output");
	foreach (@rules) {
		($self->get_string("$_/protocol") eq $protocol) or next;
		($self->get_int("$_/port") eq $port) or next;
		$self->delete_dir($_);
		return;
	}
}

# arguments:
# 	- string: protocol (tcp|udp)
# 	- string: protocol (tcp|udp)
sub addOutputRule {
	my ($self, $protocol, $port) = @_;

	checkProtocol($protocol, __("protocol"));
	checkPort($port, __("port"));

	$self->removeOutputRule($protocol, $port);

	my $id = "r" . int(rand(10000));
	while ($self->dir_exists("rules/output/$id")) {
		$id = "r" . int(rand(10000));
	}

	$self->set_string("rules/output/$id/protocol", $protocol);
	$self->set_int("rules/output/$id/port", $port);
}

# arguments:
# 	- string: name of the object
# 	- string: action (deny|allow)
# 	- string: protocol (tcp|udp)
#	- string: port (1-65535)
#	- string: address (cidr address or empty) [optional]
#	- string: mask (1-32 or empty) [optional]
sub addObjectRule($$$$$) {
	my ($self, $object, $action, $protocol, $port, $addr, $mask) = @_;

	_checkAction($action, __("policy"));
	checkProtocol($protocol, __("protocol"));
	checkPort($port, __("port"));
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

	my $id = "x" . int(rand(10000));
	while ($self->dir_exists("objects/$object/rules/$id")) {
		$id = "x" . int(rand(10000));
	}

	my $order = $self->_lastObjectRule($object) + 1;
	$self->set_string("objects/$object/rules/$id/name", $id);
	$self->set_string("objects/$object/rules/$id/action", $action);
	$self->set_string("objects/$object/rules/$id/protocol", $protocol);
	$self->set_int("objects/$object/rules/$id/port", $port);
	$self->set_bool("objects/$object/rules/$id/active", 1);
	$self->set_int("objects/$object/rules/$id/order", $order);
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
sub removeObjectService($$$) {
	my ($self, $object, $service) = @_;

	my $objects = EBox::Global->modInstance('objects');
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}
	checkName($service) or throw EBox::Exceptions::Internal(
			__x("Name '{srv}' is invalid", srv => $service));

	$self->delete_dir("objects/$object/services/$service");
	$self->_purgeEmptyObject($object);
}

# arguments:
# 	- string: name of the object
# 	- string: name of the service
# 	- string: policy (allow|deny)
sub setObjectService($$$$) {
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
sub Object($$) {
	my ($self, $name) = @_;
	my $hash = {};
	$hash->{policy} = $self->ObjectPolicy($name);
	$hash->{name} = $name;
	$hash->{rule} = $self->array_from_dir("objects/$name/rules");
	$hash->{servicepol} = $self->array_from_dir("objects/$name/services");
	return $hash;
}

sub _objectRuleNumber($$$) {
	my ($self, $object, $rule) = @_;
	return $self->get_int("objects/$object/rules/$rule/order");
}

sub _objectRulesOrder($$) {
	my ($self, $name) = @_;
	$self->dir_exists("objects/$name/rules") or return undef;
	return new EBox::Order($self, "objects/$name/rules");
}

sub ObjectRuleUp($$$) {
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

sub ObjectRuleDown($$$) {
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
sub ObjectRules($$) {
	my ($self, $name) = @_;
	my $order = $self->_objectRulesOrder($name);
	defined($order) or return undef;
	my @rules = $order->list;
	my @array = ();
	foreach (@rules) {
		push(@array, $self->hash_from_dir($_));
	}
	return \@array;
}

sub _lastObjectRule($$) {
	my ($self, $name) = @_;
	my $order = $self->_objectRulesOrder($name);
	defined($order) or return 0;
	return $order->highest;
}

# arguments:
# 	- string: name of the object
sub ObjectServices($$) {
	my ($self, $name) = @_;
	return $self->array_from_dir("objects/$name/services");
}

sub ObjectNames($) {
	my $self = shift;
	return $self->all_dirs_base("objects");
}

1;
