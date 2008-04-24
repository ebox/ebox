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


sub _createUserConfDir
{
  my ($self) = @_;

  my $dhcp = $self->{gconfmodule};
  
  my $dir = $dhcp->userConfDir();
  mkdir ($dir, 0755);
}


sub _addDHCPService
{
	my $serviceMod = EBox::Global->modInstance('services');

	if (not $serviceMod->serviceExists('name' => 'dhcp')) {
		 $serviceMod->addService('name' => 'dhcp',
                        'description' => __('Dynamic Host Configuration Protocol'),
			'protocol' => 'udp',
			'sourcePort' => 'any',
			'destinationPort' => 67,
			'internal' => 1,
			'readOnly' => 1);

	} else {
		 $serviceMod->setService('name' => 'dhcp',
                        'description' => __('Dynamic Host Configuration Protocol'),
			'protocol' => 'udp',
			'sourcePort' => 'any',
			'destinationPort' => 67,
			'internal' => 1,
			'readOnly' => 1);

		EBox::info("Not adding dhcp services as it already exists");
	}

    $serviceMod->save();

}

# Add tftp service on ebox-services module
sub _addTFTPService
{
    my $serviceMod = EBox::Global->modInstance('services');

    if (not $serviceMod->serviceExists('name' => 'tftp')) {
        $serviceMod->addService('name' => 'tftp',
                                'description' => __('Trivial File Transfer Protocol'),
                                'protocol' => 'udp',
                                'sourcePort' => 'any',
                                'destinationPort' => 69,
                                'internal' => 1,
                                'readOnly' => 1);

    } else {
        $serviceMod->setService('name' => 'tftp',
                                'description' => __('Trivial File Transfer Protocol'),
                                'protocol' => 'udp',
                                'sourcePort' => 'any',
                                'destinationPort' => 69,
                                'internal' => 1,
                                'readOnly' => 1);

        EBox::info("Not adding tftp service as it already exists");
    }

    $serviceMod->save();

}





sub _fwAllowServices
{
  my $fw = EBox::Global->modInstance('firewall');
  $fw->setInternalService('dhcp', 'accept');
  $fw->setInternalService('tftp', 'accept');
  $fw->saveConfigRecursive();
}

sub runGConf
{
  my ($self) = @_;

  $self->_addDHCPService();
  $self->_addTFTPService();
  $self->_fwAllowServices();
  
  $self->_createUserConfDir();
}

EBox::init();

my $dhcpMod = EBox::Global->modInstance('dhcp');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $dhcpMod,
    'version' => 2
);
$migration->execute();
