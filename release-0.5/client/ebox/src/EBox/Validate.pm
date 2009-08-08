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

package EBox::Validate;

use strict;
use warnings;

use EBox::Config;
use EBox::Exceptions::InvalidData;
use EBox::Gettext;
use EBox::NetWrappers qw(:all);
use Net::IP;

use constant IFNAMSIZ => 16; #Max length name for interfaces

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS  = (all => [qw{    checkCIDR checkIP checkNetmask 
					checkIPNetmask	
					checkProtocol checkPort
					checkName checkMAC checkVifaceName
					checkDomainName isIPInNetwork
				} ],
			);
	@EXPORT_OK = qw();
	Exporter::export_ok_tags('all');
	$VERSION = EBox::Config::version;
}

# boolean
# isIPInNetwork ($$$)
#
# Check if a IP is in a network
sub isIPInNetwork # net_ip, net_mask, host_ip
{
	my ($net_ip, $net_mask, $host_ip) = @_;
	my $net_net = ip_network($net_ip, $net_mask);
	
	my $bits = bits_from_mask($net_mask);
	my $ip = new Net::IP("$net_net/$bits");
	my $ip2 = new Net::IP($host_ip);
	return ($ip2->overlaps($ip)==$IP_A_IN_B_OVERLAP);
}

# boolean
# checkCIDR ($)
# $ a string param that holds an cidr block to check.
# 
# Check if the string param that holds an cidr block is a valid cidr block.

sub checkCIDR # (cidr, name?)
{
	my $cidr = shift;
	my $name = shift;

	my $ip;

	my @values = split(/\//, $cidr);

	if(@values == 2) {
		my ($address,$mask)  = @values;
		if(checkIP($address)) {
			my $netmask = mask_from_bits($mask);
			if($netmask){
				my $network = ip_network($address, $netmask);
				$ip = new Net::IP("$network/$mask");
			}
		}
	}

	unless($ip) {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $cidr);
		} else {
			return undef;
		}
	}
	return 1;
}

# boolean
# checkIP ($)
# $ a string param that holds an ip address to check
#
# Check if the string param that holds an ip address is a valid IPv4 address.

sub checkIP # (ip, name?) 
{
	my $ip = shift;
	my $name = shift;

	if("$ip\." =~ m/^(([01]?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){4}$/){
		my $first = (split(/\./, $ip))[0];
		if(($first != 0) and ($first < 224)) {
			return 1;
		}
	}
	if ($name) {
		throw EBox::Exceptions::InvalidData
			('data' => $name, 'value' => $ip);
	} else {
		return undef;
	}
}

# boolean
# checkNetmask ($)
# $ a string param that holds a netmask to check.
# 
# Check if the string param that holds a netmask is a valid netmask.

sub checkNetmask # (mask, name?) 
{
	my $nmask = shift;
	my $name = shift;
	my $error;

	if("$nmask\." =~ m/^(([01]?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){4}$/){
		my $bits;
		foreach (split(/\./, $nmask)){
		 	$bits .= unpack( "B*", pack( "C", $_ ));	
		}
		unless ($bits =~ /^((0+)|(1+0*))$/){
			$error = 1;
		}
	} else {
		$error = 1;
	}

	if ($error) {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $nmask);
		} else {
			return undef;
		}
	}
	return 1;
}

# boolean
# checkIPNetmask ($$)
# 
# Check if the IP and the mask are valid and that the IP is not a network or
# broadcast address with the given mask
# Note that both name_ip and name_mask should be set, or not set at all
sub checkIPNetmask # (ip, mask, name_ip?, name_mask?) 
{
	my ($ip,$mask,$name_ip, $name_mask) = @_;
	my $error = 0;

	checkIP($ip,$name_ip);
	checkNetmask($mask,$name_mask);

	my $ip_bpack = pack("CCCC", split(/\./, $ip));
	my $mask_bpack = pack("CCCC", split(/\./, $mask));

	my $net_bits .= unpack("B*", $ip_bpack & (~$mask_bpack));
	my $broad_bits .= unpack("B*", $ip_bpack | $mask_bpack);

	if(($net_bits =~ /^0+$/) or ($broad_bits =~ /^1+$/)){
		$error = 1;
	}
	if ($error) {
		if ($name_ip) {
			throw EBox::Exceptions::InvalidData
				('data' => $name_ip . "/" . $name_mask,
				 'value' => $ip . "/" . $mask);
		} else {
			return undef;
		}
	}
	return 1;
}

# boolean
# checkPort ($)
# $ a scalar param that holds a string
#
# Check if the scalar param holds a correct port number.

sub checkPort # (port, name?) 
{
	my $pnumber = shift;
	my $name = shift;

	unless($pnumber =~/^\d+$/){
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $pnumber);
		} else {
			return undef;
		}
	}

	if (($pnumber > 0)&&($pnumber<65535)) {
		return 1;
	} else {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $pnumber);
		} else {
			return undef;
		}
	}
}

# boolean
# checkProtocol ($)
# $ a scalar param that holds a protocol name to check;

sub checkProtocol # (protocol, name?) 
{
	my $proto = shift;
	my $name = shift;

	if ($proto eq "tcp") {
		return 1;
	} elsif ($proto eq "udp") {
		return 1;
	} else {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $proto);
		} else {
			return undef;
		}
	}
}

sub checkMAC # (mac, name?) 
{
	my $mac = shift || '';
	my $name = shift;
        $mac .= ':';
	unless ($mac =~ /^([0-9a-fA-F]{1,2}:){6}$/) {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $mac);
		} else {
			return undef;
		}
	}

	return 1;

}

# Check if a virtual interface name is correct 
# The whole name ( real + virtual interface) must be minor than IFNAMSIZ
# Only alphanumeric chars are accepted
sub checkVifaceName # (real, virtual, name?) 
{
	my $iface  = shift;
	my $viface = shift;
	my $name   = shift;
	
	my $fullname = $iface . ":" . $viface;
	unless (($viface =~ /^\w+$/) and (length($fullname) < IFNAMSIZ)){
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $viface);
		} else {
			return undef;
		}
	}	
	return 1;
}
# arguments:
# 	- string: a name to be validated
# returns:
# 	- true if the name is valid
# 	- false if the name is not valid
# A name is valid if:
# 	- starts with a letter
# 	- contains only letters, numbers and '_'
#	- isn't longer than 20 characters
sub checkName # (name) 
{
	my $name = shift;
	(length($name) <= 20) or return undef;
	(length($name) > 0) or return undef;
	($name =~ /^[\d_]/) and return undef;
	($name =~ /^\w/) or return undef;
	($name =~ /\W/) and return undef;
	return 1;
}

sub _checkDomainName {
	my $d = shift;
	($d =~ /^\w/) or return undef;
	($d =~ /\w$/) or return undef;
	($d =~ /\.-/) and return undef;
	($d =~ /-\./) and return undef;
	($d =~ /\.\./) and return undef;
	($d =~ /^[-\.\w]+$/) or return undef;
	return 1;
}

sub checkDomainName # (domain, name?)
{
	my $domain = shift;
	my $name = shift;

	unless (_checkDomainName($domain)) {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $domain);
		} else {
			return undef;
		}
	}
	return 1;
}

1;
