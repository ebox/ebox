#!/usr/bin/perl

package EBox::Migration;
use base 'EBox::MigrationBase';

use strict;
use warnings;

use EBox;
use EBox::Global;
use EBox::Gettext;
use Error qw(:try);

sub runGConf
{
    my ($self) = @_;

    $self->addInternalService(
			      'name' => 'ntp',
			      'protocol' => 'udp',
			      'sourcePort' => 'any',
			      'destinationPort' => 123,
			     );
 
}

EBox::init();

my $ntpMod = EBox::Global->modInstance('ntp');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $ntpMod,
    'version' => 1
);
$migration->execute();
