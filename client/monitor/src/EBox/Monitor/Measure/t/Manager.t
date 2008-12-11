#!/usr/bin/perl -w

# Copyright (C) 2008 eBox Technologies S.L.
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

# A module to test Manager measure module

use Test::Deep;
use Test::More qw(no_plan);
use Test::Exception;

BEGIN {
    diag ( 'Starting EBox::Monitor::Measure::Manager test' );
    use_ok( 'EBox::Monitor::Measure::Manager' )
      or die;
}

my $manager;
lives_ok {
    $manager = EBox::Monitor::Measure::Manager->Instance();
} 'Getting an instance of the manager';

isa_ok($manager, 'EBox::Monitor::Measure::Manager');

is( $manager, EBox::Monitor::Measure::Manager->Instance(),
    'Testing singleton instance');

throws_ok {
    $manager->register('Foo::Bar');
} 'EBox::Exceptions::Internal', 'Cannot load a non existant class';

throws_ok {
    $manager->register('EBox::Module');
} 'EBox::Exceptions::InvalidType', 'Cannot register a non measure class';

ok($manager->register('EBox::Monitor::Measure::Load'),
   'Registering was going well');

ok($manager->register('EBox::Monitor::Measure::CPU'),
   'Registering another one was going well');

my $measures;
lives_ok {
    $measures = $manager->measures();
} 'Getting the measure instances';

cmp_deeply($measures,
           array_each(isa('EBox::Monitor::Measure::Base')),
          'All measures are measures classes');

cmp_ok(@{$measures}, '==', 2, 'Two measures are registered');

1;
