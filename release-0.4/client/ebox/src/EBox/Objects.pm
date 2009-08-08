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
use EBox::Gettext;

use Net::IPv4Addr qw(:all);

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'objects');
	bless($self, $class);
	return $self;
}

## api functions

sub ObjectsArray
{
	my $self = shift;
	my @array = ();
	my @objs = @{$self->all_dirs_base("")};
	foreach (@objs) {
		my $hash = $self->hash_from_dir($_);
		$hash->{name} = $_;
		$hash->{member} = $self->array_from_dir($_);
		push(@array, $hash);
	}
	return \@array;
}

sub ObjectMembers # (object) 
{
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
sub ObjectDescription  # (object) 
{
	my ( $self, $object ) = @_;
	$self->dir_exists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);
	return $self->get_string("$object/description");
}

sub ObjectNames
{
	my $self = shift;
	return $self->all_dirs_base("");
}

sub ObjectAddresses  # (object) 
{
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
sub objectInUse # (object) 
{
	my ($self, $object ) = @_;
	my $global = EBox::Global->getInstance();
	my @mods = @{$global->modNames};
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
sub objectExists # (name) 
{
	my ($self, $object ) = @_;
	return $self->dir_exists($object);
}

#adds a new Object
sub addObject # (description) 
{
	my ($self, $desc ) = @_;
	
	unless (defined($desc) && $desc ne "") {
		throw EBox::Exceptions::DataMissing
			('data' => __('Object description'));
	}

	my $id = $self->get_unique_id("x");

	$self->set_string("$id/description", $desc);
	return $id;
}

#deletes the Object passed as parameter
sub _removeObject  # (object) 
{
	my ($self, $object)  = @_;
	unless (defined($object) && $object ne "") {
		return;
	}
	if ($self->dir_exists($object)){
		$self->delete_dir($object);
		return 1;
	} else {
		return undef;
	}
}

sub removeObjectForce # (object) 
{
	my ($self, $object)  = @_;
	my $global = EBox::Global->getInstance();
	my @mods = @{$global->modNames};
	foreach (@mods) {
		my $mod = $global->modInstance($_);
		$mod->freeObject($object);
	}
	return $self->_removeObject($object);
}

sub removeObject # (object) 
{
	my ($self, $object)  = @_;
	if ($self->objectInUse($object)) {
		throw EBox::Exceptions::DataInUse('data' => __('Object'),
						  'value' => $object);
	} else {
		return $self->_removeObject($object);
	}
}

#adds a IP or NETWORK to an Object
# returns 0 when successfull or throws an exception.
# in another Object
sub addToObject  # (object, ip, mask, mac?, description?) 
{
	my ( $self, $object, $ip, $mask, $mac, $nname ) = @_;

	$self->dir_exists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);

	checkIP($ip, "IP address");
	checkCIDR("$ip/$mask", "Network address");
	if ($mac){
		checkMAC($mac, "Hardware address");
	} else {
		$mac = "";
	}
	
	if ($self->alreadyInObject($ip, $mask)) {
		throw EBox::Exceptions::DataInUse('data' => __('network address'),
						  'value' => "$ip/$mask");
	}

	my $id = $self->get_unique_id("m", $object);

	$self->set_string("$object/$id/nname", $nname);
	$self->set_string("$object/$id/ip", $ip);
	$self->set_string("$object/$id/mac", $mac);
	$self->set_int("$object/$id/mask", $mask);
	
	return 0;
}

#deletes a IP or NETWORK from an Object
sub removeFromObject  # (object, id)
{
	my ( $self, $object, $id )  = @_;

	$self->dir_exists($object) or 
		throw EBox::Exceptions::DataNotFound('data' => __('Object'),
						     'value' => $object);

	if($self->dir_exists("$object/$id")) {
		$self->delete_dir("$object/$id");
		return 1;
	} else {
		return undef;
	}
}
	
sub alreadyInObject # (ip, mask) 
{
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
