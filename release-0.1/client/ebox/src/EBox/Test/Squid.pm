package EBox::Test::Squid;

use strict;
use warnings;

use XML::Simple;
use EBox::Module;
use EBox::Squid;
use EBox::Config;
use Test::Unit::Procedural;

my $squid = undef;

sub set_up {
	$squid = EBox::Squid->new();
	$squid->setConfdir(EBox::Config::confdir . 'tests');
	$squid->readConfig();
}

sub tear_down {
}
