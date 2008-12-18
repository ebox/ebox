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

# Class: EBox::Monitor::Model::ThresholdConfiguration
#
# This class is the model base to configurate thresholds for the different measures
#
# These fields are the common to all measures:
#
#    - enabled - Boolean enable/disable a threshold
#    - warningMin - Float the minimum value to start notifying a warning
#    - failureMin - Float the minimun value to start notifying a failure
#    - warningMax - Float the maximum value to start notifying a warning
#    - failureMax - Float the maximum value to start notifying a failure
#    - invert - Boolean the change the meaning of the bounds
#    - persist - Boolean the notification must be constantly sent or not
#
# These ones are dependant on the measure, that is the parent model
#

package EBox::Monitor::Model::ThresholdConfiguration;

use base 'EBox::Model::DataTable';

# eBox uses
use EBox::Exceptions::DataNotFound;
use EBox::Gettext;
use EBox::Global;
use EBox::Monitor;
use EBox::Types::Boolean;
use EBox::Types::Float;

# Core modules
use Error qw(:try);

# Constants
use constant RESOLUTION => EBox::Monitor::QueryInterval();

# Group: Public methods

# Constructor: new
#
#     Create the threshold configuration model instance
#
# Overrides:
#
#     <EBox::Model::DataTable::new>
#
# Returns:
#
#     <EBox::Monitor::Model::ThresholdConfiguration>
#
sub new
{
      my $class = shift;

      my $self = $class->SUPER::new(@_);
      bless ( $self, $class);

      return $self;

}

# Group: Protected methods

# Method: _table
#
# Overrides:
#
#     <EBox::Model::DataTable::_table>
#
sub _table
{
    my ($self) = @_;

    my @tableDesc =
      (
          new EBox::Types::Float(
              fieldName     => 'warningMin',
              printableName => __('Warning minimum'),
              optional      => 1,
              editable      => 1,
             ),
          new EBox::Types::Float(
              fieldName     => 'failureMin',
              printableName => __('Failure minimum'),
              optional      => 1,
              editable      => 1,
             ),
          new EBox::Types::Float(
              fieldName     => 'warningMax',
              printableName => __('Warning maximum'),
              optional      => 1,
              editable      => 1,
             ),
          new EBox::Types::Float(
              fieldName     => 'failureMax',
              printableName => __('Failure maximum'),
              optional      => 1,
              editable      => 1,
             ),
          new EBox::Types::Boolean(
              fieldName     => 'invert',
              printableName => __('Invert'),
              defaultValue  => 0,
              editable      => 1,
             ),
          new EBox::Types::Boolean(
              fieldName     => 'persist',
              printableName => __('Persistent'),
              defaultValue  => 1,
              editable      => 1,
             ),
          #        new EBox::Monitor::Types::MeasureAttr(
          #            fieldName     => 'measureInstance',
          #            printableName => __('Measure instance'),
          #            attribute     => 'measureIntance',
          #           ),
          #        new EBox::Monitor::Types::MeasureAttr(
          #            fieldName     => 'typeInstance',
          #            printableName => __('Type'),
          #            attribute     => 'typeInstance',
          #           ),
          #        new EBox::Monitor::Types::MeasureAttr(
          #            fieldName     => 'dataSource',
          #            printableName => __('Data Source'),
          #            attribute     => 'dataSource',
                   );

    my $dataTable = {
        tableName           => 'ThresholdConfiguration',
        printableTableName  => __('Threshold configuration'),
        modelDomain         => 'Monitor',
        printableRowName    => __('Threshold'),
        defaultActions      => [ 'add', 'del', 'editField', 'changeView' ],
        tableDescription    => \@tableDesc,
        class               => 'dataTable',
        help                => __x('Every check is done with the highest possible '
                                     . 'resolution: {nSec} seconds', nSec => RESOLUTION),
        enableProperty      => 1,
        defaultEnabledValue => 1,
        automaticRemove => 1,
    };

    return $dataTable;

}

1;
