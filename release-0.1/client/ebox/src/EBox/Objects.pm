package EBox::Objects;

use strict;
use warnings;

use base 'EBox::XMLModule';

use EBox::Validate;
use EBox::Global;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataInUse;
use EBox::Exceptions::DataMissing;
use EBox::Exceptions::DataNotFound;

use Net::IPv4Addr qw(:all);

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub _create {
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'objects');
	bless($self, $class);
	return $self;
}

## api functions

#returns a hash with the Object's
sub getObjects () {
	my $self = shift;
	return $self->hdoc->{object};
}

#returns an array with the Object's (useful for templates)
sub getObjectsArray () {
	my $self = shift;
	unless (defined($self->adoc->{object})) { 	
		return (); 
	}
	my $array = $self->adoc->{object};
	return $array;
}

#returns an array containing the IP addresses of the Object passed as parameter
sub getObject ($$) {
	my ( $self, $object ) = @_;
	return $self->hdoc->{object}->{$object}->{member};
}

# Returns the description of an Object
# arguments:
# 	- the name of an Object
# returns:
# 	- description of the Object
# throws: 
# 	- DataNotFound if the Object does not exist
sub getObjectDescription ($$) {
	my ( $self, $object ) = @_;
	$self->objectExists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);
	return $self->hdoc->{object}->{$object}->{description};
}

sub getObjectNames($) {
	my $self = shift;
	my %aux = %{$self->getObjects};
	return keys(%aux);
}

sub getObjectAddresses ($$) {
	my ( $self, $object ) = @_;
	defined($self->hdoc->{object}->{$object}) or return undef;
	my @array = @{$self->hdoc->{object}->{$object}->{member}};

	my @addresses = ();
	foreach (@array) {
		push(@addresses, $_->{ip} . "/" . $_->{mask});
	}
	return \@addresses;
}

# Asks all installed modules if they are currently using an Object.
# arguments:
# 	- the name of an Object
# returns:
# 	- true if there is a module which uses the Object
# 	- false if no module uses the Object
sub objectInUse($$) {
	my ($self, $object ) = @_;
	my $global = EBox::Global->modInstance('global');
	my @mods = $global->modNames;
	foreach (@mods) {
		my $mod = $global->modInstance($_);
		if ($mod->usesObject($object)) {
			return 1;
		}
	}
	return undef;
}

# arguments:
# 	- the name of an Object
# returns:
# 	- true if the Object exists
# 	- false otherwise
sub objectExists($$) {
	my ($self, $object ) = @_;
	return defined($self->hdoc->{object}->{$object});
}

#adds a new Object
sub addObject ($$) {
	my ($self, $object ) = @_;
	my $id = "x343";
	
	if ($object eq "") {
		throw EBox::Exceptions::DataMissing('data' => __('Object description'));
	}
	
	$id = "x" . int(rand(10000));	
	while(defined($self->hdoc->{object}->{$id})){ 
		$id = "x" . int(rand(10000));
	}
	$self->hdoc->{object}->{$id}={};	
	$self->hdoc->{object}->{$id}->{description} = $object;
	$self->writeHashFile;
}

#deletes the Object passed as parameter
sub _delObject ($$) {
	my ($self, $object)  = @_;
	delete $self->hdoc->{object}->{$object};
	if (keys(%{$self->hdoc->{object}}) == 0) {
		delete $self->hdoc->{object};
	}
	$self->writeHashFile;
}

sub delObjectForce($$) {
	my ($self, $object)  = @_;
	my $global = EBox::Global->modInstance('global');
	my @mods = $global->modNames;
	foreach (@mods) {
		my $mod = $global->modInstance($_);
		$mod->freeObject($object);
	}
	$self->_delObject($object);
}

sub delObject($$) {
	my ($self, $object)  = @_;
	if ($self->objectInUse($object)) {
		throw EBox::Exceptions::DataInUse('data' => __('Object'),
						  'value' => $object);
	} else {
		$self->_delObject($object);
	}
}

#adds a IP or NETWORK to an Object
# returns 0 when successfull or throws an exception.
# in another Object
sub addToObject ($$$$$) {
	my ( $self, $object, $ip, $mask, $nname ) = @_;

	unless (EBox::Validate::checkIP($ip)) {
		throw EBox::Exceptions::InvalidData
			('data' => 'IP address', 'value' => $ip);
	}
	unless (EBox::Validate::checkCIDR("$ip/$mask")) {
		throw EBox::Exceptions::InvalidData
			('data' => 'Network address', 'value' => "$ip/$mask");
	}
	
	if ($self->alreadyInObject($ip, $mask)) {
		throw EBox::Exceptions::DataInUse('data' => __('network address'),
						  'value' => "$ip/$mask");
	}
	
	if (defined($self->hdoc->{object}->{$object}->{member})){
		my $array = $self->hdoc->{object}->{$object}->{member};
		push (@$array, { 'ip' => $ip, 'mask' => $mask,
				 'nname' => $nname } );
	} else {
		my $array = ();
		push (@$array, { 'ip' => $ip, 'mask' => $mask,
				 'nname' => $nname } );
		$self->hdoc->{object}->{$object}->{member} = $array;
	}
	$self->writeHashFile;
	return 0;
}

#deletes a IP or NETWORK from an Object
sub delFromObject ($$$) {
	my ( $self, $object, $ip, $mask )  = @_;
	my @networks = @{$self->hdoc->{object}->{$object}->{member}};

	my $index;
	# FIXME : this is really really really ugly!!
	for($index = 0; 
	    ($ip ne $networks[$index]->{ip}) and 
	    ($mask ne $networks[$index]->{mask}) and
	    ($index <= $#networks); 
	    $index++){};
	if ($index != ($#networks+1)){
		splice (@networks,$index,1);
		@{$self->hdoc->{object}->{$object}->{member}} = @networks;

	}
	$self->writeHashFile;
}
	
sub alreadyInObject($$$) {
	#FIXME now we test the same ip, but we should test the same name?
	my ( $self, $iparg, $maskarg ) = @_;
	my $nodeset = $self->xpdoc->find('/objects/object/member');
	my $network = "$iparg/$maskarg";

	foreach my $node ($nodeset->get_nodelist) {
		my $ip = $node->getAttribute('ip');
		my $mask = $node->getAttribute('mask');
		if (ipv4_in_network("$ip/$mask", $network) or
		    ipv4_in_network($network, "$ip/$mask")) {
			return 1;
		}
	}
	return undef;
}

1;
