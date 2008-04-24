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


  my $soapMod = EBox::Global->modInstance('soap');
  $self->addInternalService(
              			 'name' => 'soap',
                                'protocol'        => 'tcp',
                                'sourcePort'      => 'any',
                                'destinationPort' => $soapMod->listeningPort(),
			   );
}

EBox::init();

my $soapMod = EBox::Global->modInstance('soap');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $soapMod,
    'version' => 1
);
$migration->execute();
