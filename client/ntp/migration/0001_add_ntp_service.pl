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


sub _addNTPService
{

    my $serviceMod = EBox::Global->modInstance('services');

	if (not $serviceMod->serviceExists('name' => 'ntp')) {
		 $serviceMod->addService('name' => 'ntp',
			'protocol' => 'udp',
			'sourcePort' => 'any',
			'destinationPort' => 123,
			'internal' => 1,
			'readOnly' => 1);
		
	} else {
          $serviceMod->setService('name' => 'ntp',
			'protocol' => 'udp',
			'sourcePort' => 'any',
			'destinationPort' => 123,
			'internal' => 1,
			'readOnly' => 1);

		EBox::info("Not adding ntp services as it already exists");
	}

    $serviceMod->saveConfig();
}


sub runGConf
{
    my ($self) = @_;

    $self->_addNTPService();

    # add firewall rule for NTP service
    my $fw = EBox::Global->modInstance('firewall');
    $fw->setInternalService('ntp', 'accept');
    $fw->save();
}

EBox::init();

my $ntpMod = EBox::Global->modInstance('ntp');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $ntpMod,
    'version' => 1
);
$migration->execute();
