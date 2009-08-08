package EBox::Test::Objects;

use strict;
use warnings;

use XML::Simple;
use EBox::Module;
use EBox::Objects;
use EBox::Config;
use Test::Unit::Procedural;

my $objects = undef;

sub set_up {
	$objects = new EBox::Objects;
	$objects->setConfdir(EBox::Config::confdir . 'tests');
	$objects->readConfig();
}

sub tear_down {
}
