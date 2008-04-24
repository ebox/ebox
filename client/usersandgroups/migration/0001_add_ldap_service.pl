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
			    'name' => 'ldap',
			    'protocol' => 'tcp',
			    'sourcePort' => 'any',
			    'destinationPort' => 389,
			    'target'  => 'deny',
			   );
}

EBox::init();

my $usersMod = EBox::Global->modInstance('users');
my $migration =  __PACKAGE__->new( 
    'gconfmodule' => $usersMod,
    'version' => 1
);
$migration->execute();
