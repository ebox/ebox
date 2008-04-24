#!/usr/bin/perl


package EBox::Migration;
use base 'EBox::MigrationBase';

use strict;
use warnings;



use EBox;
use EBox::Global;
use EBox::Gettext;
use Data::Dumper;
use EBox::Model::ModelManager;
use Socket;
use Error qw(:try);




sub _addDNSService
{
   my $serviceMod = EBox::Global->modInstance('services');

   if (not $serviceMod->serviceExists('name' => 'dns')) {
       $serviceMod->addService('name' => 'dns',
           'protocol' => 'udp',
           'sourcePort' => 'any',
           'destinationPort' => 53,
           'internal' => 1,
	   'readOnly' => 1);

   } else {
       $serviceMod->setService('name' => 'dns',
           'protocol' => 'udp',
           'sourcePort' => 'any',
           'destinationPort' => 53,
           'internal' => 1,
	   'readOnly' => 1);
       EBox::info("Not adding dns service as it already exists");
   }

   $serviceMod->save();

}



sub _fwAllowDNSService
{
  my $fw = EBox::Global->modInstance('firewall');
  $fw->setInternalService('dns', 'accept');
  $fw->saveConfigRecursive();
}

sub runGConf
{
  my ($self) = @_;
  
  $self->_addDNSService();
  $self->_fwAllowDNSService();
}

EBox::init();

my $dnsMod = EBox::Global->modInstance('dns');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $dnsMod,
    'version' => 3
);
$migration->execute();
