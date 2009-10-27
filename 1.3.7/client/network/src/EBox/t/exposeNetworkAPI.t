# Copyright (C) 2007 Warp Networks S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Unit test to check the Network API exposition

use strict;
use warnings;

use lib '../../';

use EBox::Global;

use Test::More tests => 18;
use Test::Exception;

BEGIN {
    diag( 'Starting network exposed API unit test' );
    use_ok('EBox::Network');
}

my $netMod = EBox::Global->modInstance('network');
isa_ok( $netMod, 'EBox::Network');

# Static route model
diag('Testing EBox::Network::Model::StaticRoute model');
my $addedId;
ok( $addedId = $netMod->addRoute( network => '1.1.0.0/24',
                                  gateway => '10.0.0.1',
                                  description => 'foobar' ),
    'Adding a route');

lives_ok {
    $netMod->changeGateway( '1.1.0.0/24', '10.0.0.2' );
} 'Changing gateway for the currently added static route';

my $nRoutes;
lives_ok {
    $nRoutes = @{$netMod->routes()};
} 'Getting the static routes number';

cmp_ok( $nRoutes , '>=', 1, 'Checking the static routes number');

lives_ok {
    $netMod->delRoute( '1.1.0.0/24' );
} 'Deleting a route';

cmp_ok( @{$netMod->routes()}, '==', $nRoutes - 1,
        'The route was deleted correctly');

# DNS resolver model
diag('Testing EBox::Network::Model::DNSResolver model');
my $addedId;
ok( $addedId = $netMod->addNS(nameserver => '10.0.0.1'),
    'Adding a NS resolver');

my $nNSs;
lives_ok {
    $nNSs = @{$netMod->nameservers()};
} 'Getting the nameservers';

cmp_ok( $nNSs, '>=', 1, 'NS resolver added correctly');

lives_ok {
    $netMod->setNS(0, '10.0.0.2');
} 'Updating the currently new Nameserver';

cmp_ok( $netMod->nameserverOne(), 'eq', '10.0.0.2',
        'Updated was done correctly');

lives_ok {
    $netMod->setNameservers('10.0.0.1', '10.0.0.3', '10.0.0.4');
} 'Setting whole bunch of NS resolvers';

cmp_ok( $netMod->nameserverTwo(), 'eq', '10.0.0.3',
       'Nameserver two was set correctly');

lives_ok {
    $netMod->removeNS(0);
} 'Remove the added nameserver';

cmp_ok( @{$netMod->nameservers()}, '==', $nNSs + 1,
        'The NS resolver was removed correctly');

lives_ok {
    $netMod->removeNS(0);
    $netMod->removeNS(0);
} 'Cleaning up the ns resolvers array';
