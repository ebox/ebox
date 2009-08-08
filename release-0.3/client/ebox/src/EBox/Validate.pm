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

package EBox::Validate;

use strict;
use warnings;

use EBox::Config;
use EBox::Exceptions::InvalidData;
use EBox::Gettext;
use Net::IPv4Addr qw( :all );

use constant IFNAMSIZ => 16; #Max length name for interfaces

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS  = (all => [qw{    checkCIDR checkIP checkNetMask 
					checkProtocol checkPort
					checkName checkMAC checkVifaceName
				} ],
			);
	@EXPORT_OK = qw();
	Exporter::export_ok_tags('all');
	$VERSION = EBox::Config::version;
}

# boolean
# checkCIDR ($)
# $ a string param that holds an cidr block to check.
# 
# Check if the string param that holds an cidr block is a valid cidr block.

sub checkCIDR {
	my $cidrstr = shift;
	my $name = shift;

	eval {
		my ($cidr, $msklen) = ipv4_parse($cidrstr);
	};
	if ($@) {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $cidrstr);
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

sub checkIP {
	my $ipstr = shift;
	my $name = shift;

	my $ip = ipv4_chkip($ipstr) ;

	unless (defined($ip) and ($ip eq $ipstr)) {
		if ($name) {
			throw EBox::Exceptions::InvalidData
				('data' => $name, 'value' => $ipstr);
		} else {
			return undef;
		}
	}

	return 1;
}

# boolean
# checkNetMask ($)
# $ a string param that holds a netmask to check.
# 
# Check if the string param that holds a netmask is a valid netmask.

sub checkNetMask {
	my $str = shift;
	my $name = shift;
	my $error;

	my $nmask = ipv4_chkip($str);
	if (defined($nmask) and ($nmask eq $str)) {
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
				('data' => $name, 'value' => $str);
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

sub checkPort {
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

sub checkProtocol {
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

sub checkMAC {
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
sub checkVifaceName($$;$) {
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
# 	- contains only letters and numbers
#	- isn't longer than 12 characters
sub checkName($) {
	my $name = shift;

	# TODO
	return 1;
}

1;
