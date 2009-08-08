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

package EBox::Objects;

use strict;
use warnings;

use base 'EBox::GConfModule';

use EBox::Validate qw( :all );
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

sub getObjectsArray($) {
	my $self = shift;
	my @array = ();
	my @objs = $self->all_dirs_base("");
	foreach (@objs) {
		my $hash = $self->hash_from_dir($_);
		$hash->{name} = $_;
		$hash->{member} = $self->array_from_dir($_);
		push(@array, $hash);
	}
	return \@array;
}

sub getObjectMembers($$) {
	my ( $self, $object ) = @_;
	return $self->array_from_dir($object);
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
	$self->dir_exists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);
	return $self->get_string("$object/description");
}

sub getObjectNames($) {
	my $self = shift;
	return $self->all_dirs_base("");
}

sub getObjectAddresses ($$) {
	my ( $self, $object ) = @_;
	my @array = $self->all_dirs("$object");

	my @addresses = ();
	foreach (@array) {
		push(@addresses, $self->get_string("$_/ip") . "/" .
				 $self->get_int("$_/mask"));
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
	return $self->dir_exists($object);
}

#adds a new Object
sub addObject($$) {
	my ($self, $desc ) = @_;
	
	unless (defined($desc) && $desc ne "") {
		throw EBox::Exceptions::DataMissing
			('data' => __('Object description'));
	}
	
	my $id = "x" . int(rand(10000));	
	while ($self->dir_exists($id)) { 
		$id = "x" . int(rand(10000));
	}
	$self->set_string("$id/description", $desc);
}

#deletes the Object passed as parameter
sub _delObject ($$) {
	my ($self, $object)  = @_;
	unless (defined($object) && $object ne "") {
		return;
	}
	$self->delete_dir($object);
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
sub addToObject ($$$$$$) {
	my ( $self, $object, $ip, $mask, $mac, $nname ) = @_;

	$self->dir_exists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);

	checkIP($ip, "IP address");
	checkCIDR("$ip/$mask", "Network address");
	defined($mac) or $mac = "";
	($mac ne "") and checkMAC($mac, "Hardware address");
	
	if ($self->alreadyInObject($ip, $mask)) {
		throw EBox::Exceptions::DataInUse('data' => __('network address'),
						  'value' => "$ip/$mask");
	}

	my $id = "m" . int(rand(10000));	
	while ($self->dir_exists("$object/$id")) { 
		$id = "m" . int(rand(10000));
	}

	$self->set_string("$object/$id/nname", $nname);
	$self->set_string("$object/$id/ip", $ip);
	$self->set_string("$object/$id/mac", $mac);
	$self->set_int("$object/$id/mask", $mask);
	
	return 0;
}

#deletes a IP or NETWORK from an Object
sub delFromObject ($$$) {
	my ( $self, $object, $ip, $mask )  = @_;

	$self->dir_exists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);

	my @members = $self->all_dirs($object);
	foreach (@members) {
		($self->get_string("$_/ip") eq $ip) or next;
		($self->get_int("$_/mask") eq $mask) or next;
		$self->delete_dir($_);
	}
}
	
sub alreadyInObject($$$) {
	my ( $self, $iparg, $maskarg ) = @_;
	my $network = "$iparg/$maskarg";
	my @objs = $self->all_dirs("");
	foreach (@objs) {
		my @members = $self->all_dirs($_);
		foreach(@members) {
			my $member = $self->get_string("$_/ip") . "/" .
				     $self->get_int("$_/mask");
			if (ipv4_in_network("$member", $network) or
			    ipv4_in_network($network, "$member")) {
				return 1;
			}
		}
	}
	return undef;
}

1;
