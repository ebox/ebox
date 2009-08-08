package EBox::Test::Firewall;

use strict;
use warnings;

use XML::Simple;
use EBox::Module;
use EBox::Firewall;
use EBox::Config;
use Test::Unit::Procedural;

my $fire = undef;

sub set_up {
	$fire = EBox::Firewall->new();
	$fire->setConfdir(EBox::Config::confdir . 'tests');
	$fire->readConfig();
}

sub tear_down {
}
