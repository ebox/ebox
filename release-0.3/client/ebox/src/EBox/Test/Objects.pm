# Copyright (C) 2004  Warp Netwoks S.L.
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

package EBox::Test::Objects;

use strict;
use warnings;

use EBox::Module;
use EBox::Objects;
use EBox::Config;
use Test::Unit::Procedural;

my $objects = undef;

sub set_up {
	$objects = new EBox::Objects;
	$objects->setConfdir(EBox::Config::confdir . 'tests');
	$objects->readConfig();
}

sub tear_down {
}
