# Copyright (C) 2010 eBox Technologies S.L.
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

package EBox::Squid::Composite::DelayPools;
# Class: EBox::Squid::Composite::DelayPools
#
#

use base 'EBox::Model::Composite';

use strict;
use warnings;

use EBox::Gettext;

# Group: Public methods

# Constructor: new
#
#         Constructor for the general events composite
#
# Returns:
#
#       <EBox::Squid::Model::GeneralComposite> - a
#       general events composite
#
sub new
{

      my ($class, @params) = @_;

      my $self = $class->SUPER::new(@params);

      return $self;

}

# Group: Protected methods

# Method: _description
#
# Overrides:
#
#     <EBox::Model::Composite::_description>
#
sub _description
{

    my $description =
        {
         components      => [
                             '/squid/DelayPools1',
                             '/squid/DelayPools2',
                            ],
         layout          => 'top-bottom',
         name            => 'DelayPools',
         pageTitle       => __('Bandwidth Throttling'),
         compositeDomain => 'Squid',
         help            => __('Class 1 pools allow to restrict the bandwidth rate for large downloads whereas '
                              .'Class 2 pools allow to set the bandwidth usage to a sustained rate.'),
        };

    return $description;

}

1;
