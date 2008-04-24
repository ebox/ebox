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
			    'name' => 'ipp',
			    'description' => __d('Cups printer server port'),
			    'protocol' => 'tcp',
			    'sourcePort' => 'any',
			    'destinationPort' => 631,
			   );
}

EBox::init();

my $printersMod = EBox::Global->modInstance('printers');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $printersMod,
    'version' => 1
);
$migration->execute();
