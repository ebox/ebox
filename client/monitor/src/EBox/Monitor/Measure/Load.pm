# Copyright 2008 (C) eBox Technologies S.L.
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

# Class: EBox::Monitor::Measure::Load
#
#     This measure collects the system load
#

package EBox::Monitor::Measure::Load;

use strict;
use warnings;

use base qw(EBox::Monitor::Measure::Base);

use EBox::Gettext;

# Constructor: new
#
sub new
{
    my ($class, @params) = @_;

    my $self = $class->SUPER::new(@params);
    bless($self, $class);

    return $self;
}

# Group: Protected methods

# Method: _description
#
#       Gives the description for the measure
#
# Returns:
#
#       hash ref - the description
#
sub _description
{
    return {
        printableName   => __('System load'),
        help            => __('Collect the system load that gives a rough '
                            . 'overview of the system usage'),
        dataSources     => [ 'shortterm', 'midterm', 'longterm' ],
        printableLabels => [ __('short term'), __('mid term'), __('long term') ],
        type            => 'int',
    };
}

1;
