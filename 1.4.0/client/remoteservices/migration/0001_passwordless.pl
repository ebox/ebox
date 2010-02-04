#!/usr/bin/perl

# Migration between gconf data version 0 to 1
#
# In version 1, the access setting from CC is always passwordless
#

package EBox::Migration;

use base 'EBox::Migration::Base';

use strict;
use warnings;

use EBox;
use EBox::Global;

sub runGConf
{
    my ($self) = @_;

    my $rs = $self->{gconfmodule};

    $rs->set_bool('AccessSettings/passwordless', 1);
    $rs->set_bool('AccessSettings/readOnly', 0);
    my $version = $rs->get_int('AccessSettings/version');
    $version = 0 unless defined($version);
    $rs->set_int('AccessSettings/version', $version+1);

}

EBox::init();

my $rsMod = EBox::Global->modInstance('remoteservices');
my $migration = __PACKAGE__->new(gconfmodule => $rsMod,
                                 version     => 1);

$migration->execute();
