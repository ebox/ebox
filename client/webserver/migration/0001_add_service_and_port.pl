#!/usr/bin/perl


package EBox::Migration;
use base 'EBox::MigrationBase';

use strict;
use warnings;

use EBox;
use EBox::Global;
use EBox::Gettext;
use Error qw(:try);


sub _availablePort
{
  my ($self) = @_;

  my $firewallMod = EBox::Global->modInstance('firewall');

  my $port = 80; # Default port = 80


  # Check port availability
  my $available = 0;
  do {
   $available = $firewallMod->availablePort('tcp', $port);
    $available = 1;
    unless ( $available ) {
      if ( $port == 80 ) {
	$port = 8080;
      } else {
	$port++;
      }
    }
  } until ( $available );


  return $port;
}


sub setPort
{
  my ($self, $port) = @_;

  # Save settings on the model
  my $webMod = EBox::Global->modInstance('webserver');
  my $settingsModel = $webMod->model('GeneralSettings');
  $settingsModel->set(
		      port      => $port,
		      enableDir => EBox::WebServer::Model::GeneralSettings::DefaultEnableDir(),
		     );
    $webMod->save();
}

sub runGConf
{
  my ($self) = @_;

  my $port = $self->_availablePort();
  $self->setPort($port);
  $self->addInternalService(
				    'name'            => 'http',
				    'description'     => __('HyperText Transport Protocol'),
				    'protocol'        => 'tcp',
				    'sourcePort'      => 'any',
				    'destinationPort' => $port,
				   );
}

EBox::init();

my $webserverMod = EBox::Global->modInstance('webserver');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $webserverMod,
    'version' => 1
);
$migration->execute();
