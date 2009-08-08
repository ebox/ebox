#!/usr/bin/perl -w

# Copyright (C) 2006 Warp Networks S.L.
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

# A module to test an already created TrafficShaping module

use strict;
use warnings;

use Test::More tests => 3;
use Test::Exception;
use Test::Deep;
use Data::Dumper;

use EBox::Global;
use EBox;

use lib '../..';

diag ( 'Starting EBox::TrafficShaping test' );


BEGIN {
  use_ok ( 'EBox::TrafficShaping' )
    or die;
}

EBox::init();

my $ts;
lives_ok {
  $ts = EBox::Global->modInstance( 'trafficshaping' );
}
  'Getting a traffic shaping instance';

lives_ok {
  $ts->_regenConfig();
}
  'Regeneration config';
