#!/usr/bin/perl

#  Migration between gconf data version X and Y
#
#       This migration script takes care of... TODO
#
use strict;
use warnings;

package EBox::Migration;
use base 'EBox::MigrationBase';

use strict;
use warnings;

use EBox;
use EBox::Global;
use EBox::Config;
use EBox::Sudo;
use EBox::UsersAndGroups;

use Error qw(:try);

# Method: runGConf
#
#   Overrides <EBox::MigrationBase::runGConf>
#
sub runGConf
{
    my ($self) = @_;

    my $mod =$self->{'gconfmodule'};

    my @users;
    # if LDAP is not yet initialized, users() will fail
    try {
        @users = $mod->users();
    } catch Error with {};
    foreach my $user (@users) {
        unless (EBox::UsersAndGroups::isHashed($user->{password})) {
            $mod->modifyUser($user);
        }
    }
}

# Main

EBox::init();

my $module = EBox::Global->modInstance('users');
my $migration = new EBox::Migration( 
        'gconfmodule' => $module,
        'version' => 3,
        );
$migration->execute();

1;
