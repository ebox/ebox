#!/usr/bin/perl


package EBox::Migration;
use base 'EBox::MigrationBase';

use strict;
use warnings;

use EBox;
use EBox::Global;
use EBox::Gettext;
use Error qw(:try);



sub _addSambaService
{

  my $global = EBox::Global->instance();
  my $fw = $global->modInstance('firewall');

  my $serviceMod = EBox::Global->modInstance('services');

  if (not $serviceMod->serviceExists('name' => 'samba')) {
    my @services;
    for my $port (qw(137 138 139 445)) {
      push (@services, { 'protocol' => 'tcp/udp', 
			 'sourcePort' => 'any',
			 'destinationPort' => $port });
    }
    $serviceMod->addMultipleService(
				    'name' => 'samba', 
				    'internal' => 1,
				    'description' =>  __d('File sharing (Samba) protocol'),
				    'domain' => 'ebox-samba',
				    'services' => \@services);

    $serviceMod->saveConfig();

  } else {
    EBox::info("Not adding samba service as it already exists");
  }

  $fw->setInternalService('samba', 'accept');


  $fw->saveConfig();

}



sub runGConf
{
  my ($self) = @_;

  $self->_addSambaService();
}

EBox::init();

my $sambaMod = EBox::Global->modInstance('samba');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $sambaMod,
    'version' => 1
);
$migration->execute();
