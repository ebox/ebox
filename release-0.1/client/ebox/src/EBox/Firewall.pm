package EBox::Firewall;

use strict;
use warnings;

use base 'EBox::XMLModule';

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
	my $self =$class->SUPER::_create(name => 'firewall',
					 keyattr => { object => 'name' ,
					 	      rule => 'name', 
					 	      servicepol => 'name', 
						      service => 'name'});
	bless($self, $class);
	return $self;
}

## internal utility functions

sub _checkPolicy($) {
	my $i = shift;
	if ($i eq "deny" || $i eq "allow" || $i eq "global") {
		return 1;
	}
	return 0;
}

sub _checkAction($) {
	my $i = shift;
	if ($i eq "allow" || $i eq "deny") {
		return 1;
	}
	return 0;
}

sub purgeEmptyObject($$) {
	my ($self, $object) = @_;

	if ($object eq '_global') {
		return;
	}

	defined($self->hdoc->{objects}[0]->{object}->{$object}) or return;

	if ((defined($self->hdoc->{objects}[0]->{object}->{$object}->{rule})) &&
	     (keys(%{$self->hdoc->{objects}[0]->{object}->{$object}->{rule}}) == 0)) {
		delete($self->hdoc->{objects}[0]->{object}->{$object}->{rule});
	}

	if ((defined($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol})) &&
	  (keys(%{$self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}}) == 0)) {
		delete($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol});
	}

	if (defined($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol})) {
		return;
	}
	if (defined($self->hdoc->{objects}[0]->{object}->{$object}->{rule})) {
		return;
	}
	if ($self->ObjectPolicy($object) eq 'global') {
		delete($self->hdoc->{objects}[0]->{object}->{$object});
	}
	$self->writeHashFile;

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
	return defined($self->hdoc->{objects}[0]->{object}->{$object});
}

sub freeObject($$) {
	my ($self, $object) = @_;
	if ($self->usesObject($object)) {
		delete($self->hdoc->{objects}[0]->{object}->{$object});
		$self->writeHashFile;
	}
}

# returns:
# 	- DROP|REJECT
sub denyAction($) {
	my $self = shift;
	return $self->adoc->{action}[0]->{deny};
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
	$self->adoc->{action}[0]->{deny} = $action;
	$self->writeArrayFile();
}

sub portRedirections($) {
	my $self = shift;
	defined($self->adoc->{dnats}) or return ();
	return $self->adoc->{dnats}[0]->{dnat};
}

# arguments:
# 	- string: protocol (tcp|udp)
#	- string: external port (1-65535)
#	- string: network interface
#	- string: destination address (valid IP address)
#	- string: destination port (1-65535)
sub addPortRedirection($$$$$) {
	my ($self, $proto, $eport, $iface, $address, $dport) = @_;

	checkProtocol($proto) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $proto);
	checkIP($address) or
		throw EBox::Exceptions::InvalidData(
					'data' => __("destination address"),
					'value' => $address);
	checkPort($eport) or
		throw EBox::Exceptions::InvalidData(
						'data' => __("external port"),
						'value' => $eport);
	checkPort($dport) or
		throw EBox::Exceptions::InvalidData(
					'data' => __("destination port"),
					'value' => $dport);

	unless (defined($self->adoc->{dnats})) {
		my @array = ();
		$self->adoc->{dnats} = \@array;	
	}
	unless (defined($self->adoc->{dnats}[0]->{dnat})) {
		my @array = ();
		$self->adoc->{dnats}[0]->{dnat} = \@array;	
	}
	foreach (@{$self->adoc->{dnats}[0]->{dnat}}) {
		if (($_->{protocol} eq $proto) && ($_->{eport} eq $eport)) {
			throw EBox::Exceptions::DataInUse(
				'data' =>'redirected port',
				'value' => $eport);
		}
	}
	my $size = scalar @{$self->adoc->{dnats}[0]->{dnat}};
	$self->adoc->{dnats}[0]->{dnat}[$size]->{protocol} = $proto;
	$self->adoc->{dnats}[0]->{dnat}[$size]->{eport} = $eport;
	$self->adoc->{dnats}[0]->{dnat}[$size]->{iface} = $iface;
	$self->adoc->{dnats}[0]->{dnat}[$size]->{ip} = $address;
	$self->adoc->{dnats}[0]->{dnat}[$size]->{dport} = $dport;
	$self->writeArrayFile();
}

# arguments:
# 	- string: protocol (tcp|udp)
#	- string: external port (1-65535)
#	- string: interface
sub removePortRedirection($$$$) {
	my ($self, $proto, $eport, $iface) = @_;
	my $i = 0;

	checkProtocol($proto) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $proto);
	checkPort($eport) or
		throw EBox::Exceptions::InvalidData(
						'data' => __("external port"),
						'value' => $eport);

	defined($self->adoc->{dnats}) or return;
	defined($self->adoc->{dnats}[0]->{dnat}) or return;

	foreach (@{$self->adoc->{dnats}[0]->{dnat}}) {
		if (($_->{protocol} eq $proto) &&
		    ($_->{eport} eq $eport) &&
		    ($_->{iface} eq $iface)) {
			splice(@{$self->adoc->{dnats}[0]->{dnat}}, $i, 1);
			$self->writeArrayFile();
			return;
		}
		$i++;
	}
}

sub services($) {
	my $self = shift;
	unless (defined($self->adoc->{services}[0]->{service})) {
		return ();
	}
	my $servs = $self->adoc->{services}[0]->{service};
	return $servs;
}

# arguments:
# 	- string: the name of a service
sub service($$) {
	my ($self, $name) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	defined($self->hdoc->{services}) or return undef;
	defined($self->hdoc->{services}[0]->{service}) or return undef;

	return $self->hdoc->{services}[0]->{service}->{$name};
}

# arguments:
# 	- string: name of a service
# returns:
# 	- protocol for the service: tcp|udp
sub serviceProtocol($$) {
	my ($self, $name) = @_;
	my $service = $self->service($name);
	if (!defined($service)) {
		return undef;
	}
	return $service->{protocol};
}

# arguments:
# 	- string: name of a service
# returns:
# 	- service port (1-65535)
sub servicePort($$) {
	my ($self, $name) = @_;
	my $service = $self->service($name);
	if (!defined($service)) {
		return undef;
	}
	return $service->{port};
}

# arguments:
# 	- string: name of a service, must not already exist
# 	- string: protocol (tcp|udp)
# 	- string: port (1-65535)
sub addService($$$$) {
	my ($self, $name, $proto, $port) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));
	checkProtocol($proto) or 
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $proto);
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);

	unless (defined($self->adoc->{services})) {
		my @array = ();
		$self->adoc->{services} = \@array;	
	}
	unless (defined($self->adoc->{services}[0]->{service})) {
		my @array = ();
		$self->adoc->{services}[0]->{service} = \@array;	
	}
	foreach (@{$self->adoc->{services}[0]->{service}}) {
		if (($_->{protocol} eq $proto) && ($_->{port} eq $port)) {
			throw EBox::Exceptions::DataInUse(
				'data' =>'local port',
				'value' => $port);
		}
		if ($_->{name} eq $name) {
			throw EBox::Exceptions::DataInUse(
				'data' =>'service',
				'value' => $name);
		}
	}
	my $size = scalar @{$self->adoc->{services}[0]->{service}};
	$self->adoc->{services}[0]->{service}[$size]->{protocol} = $proto;
	$self->adoc->{services}[0]->{service}[$size]->{port} = $port;
	$self->adoc->{services}[0]->{service}[$size]->{name} = $name;
	$self->writeArrayFile();
}

# arguments:
# 	- string: name of the service
sub removeService($$) {
	my ($self, $name) = @_;
	my $i = 0;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	defined($self->adoc->{services}) or return;
	defined($self->adoc->{services}[0]->{service}) or return;

	# FIXME remove the service from the Objects section too
	foreach (@{$self->adoc->{services}[0]->{service}}) {
		if ($_->{name} eq $name) {
			splice(@{$self->adoc->{services}[0]->{service}},
				$i, 1);
			$self->writeArrayFile();
			return;
		}
		$i++;
	}
} 
# arguments:
# 	- string: name of the service, must exist
# 	- string: protocol (tcp|udp)
# 	- string: port (1-65535)
sub changeService($$$$) {
	my ($self, $name, $proto, $port) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));
	checkProtocol($proto) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $proto);
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);

	$self->removeService($name);
	$self->addService($name, $proto, $port);
}

# arguments:
# 	- string: name of the service, must exist
# 	- string: dnat port (1-65535)
sub setServiceDNat($$$) {
	my ($self, $name, $port) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);

	defined($self->hdoc->{services}[0]->{service}->{$name}) or
		throw EBox::Exceptions::DataNotFound('data' => __("service"),
						     'value' => $name);

	$self->hdoc->{services}[0]->{service}->{$name}->{dnatport} = $port;
	$self->writeHashFile;
}

# arguments:
# 	- string: name of the service, must exist
sub unsetServiceDNat($$) {
	my ($self, $name) = @_;

	checkName($name) or
		throw EBox::Exceptions::Internal(
			__x("Name '{name}' is invalid", name => $name));

	defined($self->hdoc->{services}[0]->{service}->{$name}) or
		throw EBox::Exceptions::DataNotFound('data' => __("service"),
						     'value' => $name);

	defined($self->hdoc->{services}[0]->{service}->{$name}->{dnatport}) or
		return;

	delete($self->hdoc->{services}[0]->{service}->{$name}->{dnatport});
	$self->writeHashFile;
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

	my @objects = @{$self->adoc->{objects}};
	foreach (@{$objects[0]->{object}}) {
		if ($_->{name} eq $name) {
			return $_->{policy};
		}
	}
	return 'global';
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

	if (defined($self->hdoc->{objects}[0]->{object}->{$object})) {
		return;
	}

	$self->hdoc->{objects}[0]->{object}->{$object} = {};
	$self->hdoc->{objects}[0]->{object}->{$object}->{policy} = 'global';
	$self->writeHashFile();
}

# arguments:
# 	- string: name of the object
# 	- string: the default policy for the object (global|deny|allow)
sub setObjectPolicy($$$) {
	my ($self, $object, $policy) = @_;
	my $objects = EBox::Global->modInstance('objects');

	_checkPolicy($policy) or
		throw EBox::Exceptions::InvalidData('data' => __("policy"),
						    'value' => $policy);
	if ($object ne '_global') {
		$objects->objectExists($object) or
			throw EBox::Exceptions::DataNotFound(
							'data' => __("object"),
							'value' => $object);
	}


	unless (defined($self->hdoc->{objects}[0]->{object}->{$object})) {
		$self->hdoc->{objects}[0]->{object}->{$object} = {};
	}
	$self->hdoc->{objects}[0]->{object}->{$object}->{policy} = $policy;

	$self->writeHashFile();
	$self->purgeEmptyObject($object);
}

# arguments:
# 	- string: name of the object
# 	- string: name of the rule
sub removeObjectRule {
	my ($self, $object, $rule) = @_;

	$self->ObjectRuleExists($object, $rule) or return;
	delete($self->hdoc->{objects}[0]->{object}->{$object}->{rule}->{$rule});
	if (keys(%{$self->hdoc->{objects}[0]->{object}->{$object}->{rule}}) == 0) {
		delete($self->hdoc->{objects}[0]->{object}->{$object}->{rule});
	}

	$self->purgeEmptyObject($object);

	$self->writeHashFile();
}

# arguments:
# 	- string: name of the object
# 	- string: name of a rule
# returns
# 	true if the rule exists
# 	false otherwise
sub ObjectRuleExists($$$) {
	my ($self, $object, $rule) = @_;

	defined($self->hdoc->{objects}[0]->{object}->{$object}) or return undef;
	defined($self->hdoc->{objects}[0]->{object}->{$object}->{rule}) or return undef;
	defined($self->hdoc->{objects}[0]->{object}->{$object}->{rule}->{$rule}) or
		return undef;
	return 1;
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

	_checkAction($action) or
		throw EBox::Exceptions::InvalidData('data' => __("policy"),
						    'value' => $action);
	checkProtocol($protocol) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $protocol);
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);
	if (defined($addr) && $addr ne "") {
		checkCIDR($addr) or
			throw EBox::Exceptions::DataMissing(
							'data' => __("address"),
							'value' => $addr);
	}

	my $bool = "no";
	defined($active) and $bool = "yes";

	$self->ObjectRuleExists($object, $rule) or return;

	my $ref = $self->hdoc->{objects}[0]->{object}->{$object}->{rule}->{$rule};
	$ref->{action} = $action;
	$ref->{proto} = $protocol;
	$ref->{port} = $port;
	$ref->{active} = $bool;
	if (defined($addr) && $addr ne "") {
		$ref->{address} = $addr;
	} elsif (defined($ref->{address})){
		delete($ref->{address});
	}
	if (defined($mask) && $mask ne "") {
		$ref->{mask} = $mask;
	} elsif (defined($ref->{mask})) {
		delete($ref->{mask});
	}

	$self->writeHashFile();
}

sub OutputRules($) {
	my $self = shift;

	defined($self->adoc->{output}) or return undef;
	defined($self->adoc->{output}[0]->{inetrule}) or return undef;
	return $self->adoc->{output}[0]->{inetrule};
}

# arguments:
# 	- string: protocol (tcp|udp)
# 	- string: protocol (tcp|udp)
sub removeOutputRule {
	my ($self, $protocol, $port) = @_;

	checkProtocol($protocol) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $protocol);
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);

	unless (defined($self->adoc->{output})) {
		return;
	}
	unless (defined($self->adoc->{output}[0]->{inetrule})) {
		return;
	}

	my @rules = @{$self->adoc->{output}[0]->{inetrule}};
	my $i = 0;
	foreach (@rules) {
		if ($_->{port} eq $port && $_->{proto} eq $protocol) {
			splice(@{$self->adoc->{output}[0]->{inetrule}}, $i, 1);
			$self->writeArrayFile;
			last;
		}
		$i++;
	}
}

# arguments:
# 	- string: protocol (tcp|udp)
# 	- string: protocol (tcp|udp)
sub addOutputRule {
	my ($self, $protocol, $port) = @_;

	checkProtocol($protocol) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $protocol);
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);

	unless (defined($self->adoc->{output})) {
		$self->adoc->{output} = {};
	}
	unless (defined($self->adoc->{output}[0]->{inetrule})) {
		my @array = ();
		$self->adoc->{output}[0]->{inetrule} = \@array;
	}

	my @rules = @{$self->adoc->{output}[0]->{inetrule}};
	foreach (@rules) {
		if ($_->{port} eq $port && $_->{proto} eq $protocol) {
			return;
		}
	}
	my $rule = {proto => $protocol, port => $port};
	push(@{$self->adoc->{output}[0]->{inetrule}}, $rule);
	$self->writeArrayFile;
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

	_checkAction($action) or
		throw EBox::Exceptions::InvalidData('data' => __("policy"),
						    'value' => $action);
	checkProtocol($protocol) or
		throw EBox::Exceptions::InvalidData('data' => __("protocol"),
						    'value' => $protocol);
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => __("port"),
						    'value' => $port);
	if (defined($addr) && $addr ne "") {
		# FIXME : mask????
		checkCIDR($addr) or
			throw EBox::Exceptions::InvalidData(
							'data' => __("address"),
							'value' => $addr);
	}
	
	unless (defined($self->hdoc->{objects}[0]->{object}->{$object})) {
		$self->_createObject($object);
	}

	unless (defined($self->hdoc->{objects}[0]->{object}->{$object}->{rule})) {
		$self->hdoc->{objects}[0]->{object}->{$object}->{rule} = {};
	}

	my $id = "x" . int(rand(10000));
	while ($self->ObjectRuleExists($object, $id)) {
		$id = "x" . int(rand(10000));
	}

	my $ref = $self->hdoc->{objects}[0]->{object}->{$object}->{rule};

	$ref->{$id} = {};
	$ref->{$id}->{action} = $action;
	$ref->{$id}->{proto} = $protocol;
	$ref->{$id}->{port} = $port;
	$ref->{$id}->{active} = 'yes';
	$ref->{$id}->{order} = $self->_lastObjectRule($object) + 1;
	if (defined($addr) && $addr ne "") {
		$ref->{$id}->{address} = $addr;
	}
	if (defined($mask) && $mask ne "") {
		$ref->{$id}->{mask} = $mask;
	}
	$self->writeHashFile();
	# FIXME ORDER
}

# arguments:
# 	- string: name of the object
# 	- string: name of the service
sub removeObjectService($$$) {
	my ($self, $object, $service) = @_;

	checkName($service) or
		throw EBox::Exceptions::Internal(
		__x("Name '{service}' is invalid", service => $service));

	defined($self->hdoc->{objects}[0]->{object}->{$object}) or return;
	defined($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}) or return;
	defined($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}->{$service})
		or return;
	delete($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}->{$service});

	if (keys(%{$self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}}) == 0) {
		delete($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol});
	}

	$self->purgeEmptyObject($object);

	$self->writeHashFile();
}

# arguments:
# 	- string: name of the object
# 	- string: name of the service
# 	- string: policy (allow|deny)
sub setObjectService($$$$) {
	my ($self, $object, $srv, $policy) = @_;

	_checkAction($policy) or
		throw EBox::Exceptions::InvalidData('data' => __("policy"),
						    'value' => $policy);

	defined($self->hdoc->{services}[0]->{service}->{$srv}) or return;

	defined($self->hdoc->{objects}[0]->{object}->{$object}) or
		$self->_createObject($object);

	defined($self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}) or
	    $self->hdoc->{objects}[0]->{object}->{$object}->{servicepol} = {};

	$self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}->{$srv} = {};
	$self->hdoc->{objects}[0]->{object}->{$object}->{servicepol}->{$srv}->{policy} = $policy;
	$self->writeHashFile();
}

# arguments:
# 	- string: name of the object
sub Object($$) {
	my ($self, $name) = @_;
	my @objects = @{$self->adoc->{objects}};
	foreach (@{$objects[0]->{object}}) {
		if ($_->{name} eq $name) {
			return $_;
		}
	}
	return;
}

sub _objectRuleNumber($$$) {
	my ($self, $object, $rule) = @_;
	my $rules = $self->ObjectRules($object);
	defined($rules) or return 0;
	foreach (@{$rules}) {
		if ($_->{name} eq $rule) {
			return $_->{order};
		}
	}
	return 0;
}

sub _objectRulesOrder($$) {
	my ($self, $name) = @_;
	my @objects = @{$self->adoc->{objects}};
	my $ruleref = undef;
	foreach (@{$objects[0]->{object}}) {
		if ($_->{name} eq $name) {
			if (defined($_->{rule})) {
				$ruleref = $_->{rule};
			} else {
				last;
			}
		}
	}
	defined($ruleref) or return undef;

	my $order = new EBox::Order($ruleref, 'order');
	return $order;
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
	$self->writeArrayFile;
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
	$self->writeArrayFile;
}

# arguments:
# 	- string: name of the object
sub ObjectRules($$) {
	my ($self, $name) = @_;
	my $order = $self->_objectRulesOrder($name);
	defined($order) or return undef;
	return $order->list;
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
	my @objects = @{$self->adoc->{objects}};
	foreach (@{$objects[0]->{object}}) {
		if ($_->{name} eq $name) {
			if (defined($_->{servicepol})) {
				return $_->{servicepol};
			} else {
				return;
			}
		}
	}
	return;
}

sub ObjectNames($) {
	my $self = shift;
	my @objects = @{$self->adoc->{objects}};
	my @names ;
	foreach (@{$objects[0]->{object}}) {
		$names[@names] = $_->{name};
	}
	return @names;
}

sub Objects($) {
	my $self = shift;
	my @objects = @{$self->adoc->{objects}};
	return @objects;
}

1;
