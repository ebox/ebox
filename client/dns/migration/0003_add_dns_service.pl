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
			  'name' => 'dns',
			  'protocol' => 'udp',
			  'sourcePort' => 'any',
			  'destinationPort' => 53,
			 );

}

EBox::init();

my $dnsMod = EBox::Global->modInstance('dns');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $dnsMod,
    'version' => 3
);
$migration->execute();
