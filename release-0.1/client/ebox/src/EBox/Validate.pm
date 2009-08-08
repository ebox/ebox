#####################################################################
#
# A library with several functions to validate common data types.
#
# File: common/lib/validate-common.pl
# License: GPL
# License URL: http://www.gnu.org/copyleft/gpl.html
#
# Authors:
#  Ricardo Munoz <ricardo.munoz at hispalinux.es>
#
# Created: 2004 05 27 by EXUS
#
######################################################################

package EBox::Validate;

use strict;
use warnings;

use EBox::Config;
use Net::IPv4Addr qw( :all );

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS  = (all => [qw{    checkCIDR checkIP 
					checkProtocol checkPort
					checkName
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

sub checkCIDR($) {
	my $cidrstr = shift;

	eval {
		my ($cidr, $msklen) = ipv4_parse($cidrstr);
	};
	return undef if($@);
	
	return 1;
}

# boolean
# checkIP ($)
# $ a string param that holds an ip address to check
#
# Check if the string param that holds an ip address is a valid IPv4 address.

sub checkIP ($) {
	my $ipstr = shift;

	my $ip = ipv4_chkip($ipstr) ;

	return (defined($ip) and ($ip eq $ipstr));
}

# boolean
# checkPort ($)
# $ a scalar param that holds a port number to check;
#
# Check if the scalar param holds a correct port number.

sub checkPort($) {
	my $pnumber = shift;

	if (($pnumber > 0)&&($pnumber<65535)) {
		return 1;
	} else {
		return undef;
	}
}

# boolean
# checkProtocol ($)
# $ a scalar param that holds a protocol name to check;

sub checkProtocol($) {
	my $proto = shift;

	if ($proto eq "tcp") {
		return 1;
	} elsif ($proto eq "udp") {
		return 1;
	} else {
		return undef;
	}
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
