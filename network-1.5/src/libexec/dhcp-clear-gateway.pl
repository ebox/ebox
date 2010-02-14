#!/usr/bin/perl

use strict;
use warnings;

use EBox;
use EBox::Global;
use Error qw(:try);

EBox::init();

my $global = EBox::Global->getInstance(1);
my $network = $global->modInstance("network");

my ($iface) = @ARGV;
$iface or exit;

try {
	$network->DHCPGatewayCleanUp($iface);
} finally {
	exit;
};
