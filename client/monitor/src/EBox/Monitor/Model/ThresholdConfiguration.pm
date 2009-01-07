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
#    - measureInstance - Select if there are more than one measure
#    instance, it should be displayed as a select
#
#    - typeInstance - Select if there are more than one type per
#    measure, it should be displayed as a select in this combo
#
#    - dataSource - Select if there are more than one data source per
#    type, it should be displayed as a select in this combo
#
package EBox::Monitor::Model::ThresholdConfiguration;

use base 'EBox::Model::DataTable';

# eBox uses
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::External;
use EBox::Gettext;
use EBox::Global;
use EBox::Monitor;
use EBox::Monitor::Types::MeasureAttribute;
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

# Method: validateTypedRow
#
# Overrides:
#
#     <EBox::Model::DataTable::validateTypedRow>
#
sub validateTypedRow
{
    my ($self, $action, $changedFields, $allFields) = @_;

    # Check at least a threshold is set
    my $nDefined = grep { defined($_) }
      map { $allFields->{$_}->value() } qw(warningMin failureMin warningMax failureMax);
    unless($nDefined > 0) {
        throw EBox::Exceptions::External(
            __('At least a threshold (maximum or minimum) must be set')
           );
    }

    my $excStr = __('This threshold rule will override the current ones');
    # Try not to override a rule with the remainder ones
    if (exists($changedFields->{typeInstance}) or exists($changedFields->{measureInstance})
        or exists($changedFields->{dataSource}) ) {
        my $matchedRows;
        # If there two are any-any, then only a row must be on the table
        if ( $allFields->{typeInstance}->value() eq 'none'
            and $allFields->{measureInstance}->value() eq 'none'
            and $allFields->{dataSource}->value() eq 'none') {
            if ( ($action eq 'add' and $self->size() > 0)
                  or
                 ($action eq 'update' and $self->size() > 1)
                ) {
                throw EBox::Exceptions::External($excStr);
            }
        }

        if ( $allFields->{typeInstance}->value() eq 'none' ) {
            $matchedRows = $self->findAllValue(measureInstance => $allFields->{measureInstance}->value());
        } else {
            $matchedRows = $self->findAllValue(typeInstance => $allFields->{typeInstance}->value());
        }
        foreach my $row (@{$matchedRows}) {
            next if (($action eq 'update') and ($row->id() eq $allFields->{id}));
            if ( $allFields->{typeInstance}->value() eq 'none'
                 and $row->elementByName('dataSource')->isEqualTo($allFields->{dataSource})) {
                # There should be no more typeInstance with the same measure instance
                throw EBox::Exceptions::External($excStr);
            } else {
                if ( $row->elementByName('typeInstance')->isEqualTo($allFields->{typeInstance})
                     and $row->elementByName('measureInstance')->isEqualTo($allFields->{measureInstance})
                     and $row->elementByName('dataSource')->isEqualTo($allFields->{dataSource})) {
                    throw EBox::Exceptions::DataExists(
                        data  => $self->printableRowName(),
                        value => '',
                       );
                } elsif ( $row->elementByName('typeInstance')->isEqualTo($allFields->{typeInstance})
                            and
                         ( ( $row->valueByName('measureInstance') eq 'none'
                             and $row->valueByName('dataSource') eq 'none')
                            or
                           ( $allFields->{measureInstance}->value() eq 'none'
                             and $allFields->{dataSource}->value() eq 'none'))
                        ) {
                    throw EBox::Exceptions::External($excStr);
                }
            }
        }
    }

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
          new EBox::Monitor::Types::MeasureAttribute(
              fieldName     => 'measureInstance',
              printableName => __('Measure instance'),
              attribute     => 'measureInstance',
              editable      => 1,
             ),
          new EBox::Monitor::Types::MeasureAttribute(
              fieldName     => 'typeInstance',
              printableName => __('Type'),
              attribute     => 'typeInstance',
              editable      => 1,
             ),
          new EBox::Monitor::Types::MeasureAttribute(
              fieldName     => 'dataSource',
              printableName => __('Data Source'),
              attribute     => 'dataSource',
              editable      => 1,
             ),
         );

    my $dataTable = {
        tableName           => 'ThresholdConfiguration',
        pageTitle           => __('Threshold configuration'),
        printableTableName  => __(q{Threshold's list}),
        modelDomain         => 'Monitor',
        printableRowName    => __('Threshold'),
        defaultActions      => [ 'add', 'del', 'editField', 'changeView' ],
        tableDescription    => \@tableDesc,
        class               => 'dataTable',
        help                => __x('Every check is done with the highest possible '
                                     . 'resolution: {nSec} seconds', nSec => RESOLUTION) . '.<br>'
                               . __x('Take into account this configuration will be '
                                     . 'only applied if monitor {openhref}event watcher is enabled{closehref}',
                                     openhref  => '<a href="/ebox/Events/Composite/GeneralComposite">',
                                     closehref => '</a>'),
        enableProperty      => 1,
        defaultEnabledValue => 1,
        automaticRemove     => 1,
        rowUnique           => 1,
    };

    return $dataTable;

}

1;
