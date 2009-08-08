#!/usr/bin/perl

use strict;
use warnings;

use EBox::Global;
use EBox::Exceptions::Lock;
use Error qw(:try);

EBox::Global::init();

my $timeout = 60;
my $global = EBox::Global->getInstance(1);
my $fw = $global->modInstance("firewall");
my $logger = $global->logger;

while ($timeout) {
	try {
		$fw->restartService();
		exit(0);
	} catch EBox::Exceptions::Lock with {
		sleep 5;
		$timeout -= 5;
	};
}

$logger->error("DHCP hook: Firewall module has been locked for 60 seconds, ".
		"I give up.");
