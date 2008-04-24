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

sub runGConf
{
  my ($self) = @_;

  $self->addInternalService(
			    'name' => 'tftp',
			    'description' => __('Trivial File Transfer Protocol'),
			    'protocol' => 'udp',
			    'sourcePort' => 'any',
			    'destinationPort' => 69,
			   );

  $self->addInternalService(
			    'name' => 'dhcp',
			    'description' => __('Dynamic Host Configuration Protocol'),
			    'protocol' => 'udp',
			    'sourcePort' => 'any',
			    'destinationPort' => 67,
			   );
  
  $self->_createUserConfDir();
}

EBox::init();

my $dhcpMod = EBox::Global->modInstance('dhcp');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $dhcpMod,
    'version' => 2
);
$migration->execute();
