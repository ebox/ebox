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

# Class: EBox::TrafficShaping::Model::RuleTable
#
#   This class describes a model which contains rule to do traffic
#   shaping on a given interface. It serves as a model template which
#   has as many instances as interfaces have the machine managed by
#   eBox. It is a quite complicated model and it is highly coupled to
#   <EBox::TrafficShaping> module itself.
#

package EBox::TrafficShaping::Model::RuleTable;

use strict;
use warnings;

# Its parent is the EBox::Model::DataTable
use base 'EBox::Model::DataTable';

use integer;

use Error qw(:try);

use EBox::Gettext;
use EBox::Global;

use EBox::Model::ModelManager;

# eBox types! wow
use EBox::Types::Int;
use EBox::Types::Select;
# use EBox::Types::Service;
use EBox::Types::MACAddr;
use EBox::Types::IPAddr;
use EBox::Types::Union;
use EBox::Types::Union::Text;

# Uses to validate
use EBox::Validate qw( checkProtocol checkPort );

# Constants
use constant LIMIT_RATE_KEY => '/limitRate';

# Constructor: new
#
#       Constructor for Traffic Shaping Table Model
#
# Parameters:
#
#       gconfmodule -
#       directory   -
#       interface   - the interface where the table is attached
#
# Returns :
#
#      A recently created <EBox::TrafficShaping::Model::RuleTable> object
#
sub new
{

    my $class = shift;
    my (%params) = @_;

    my $self = $class->SUPER::new(@_);

    $self->{interface} = $params{interface};
    $self->{ts} = $params{gconfmodule};
    my $netMod = EBox::Global->modInstance('network');
    if ( $netMod->ifaceIsExternal($self->{interface}) ) {
        $self->{interfaceType} = 'external';
        $self->_setStateRate($self->{ts}->uploadRate($self->{interface}));
    } else {
        $self->{interfaceType} = 'internal';
        $self->_setStateRate($self->{ts}->totalDownloadRate());
    }

    bless($self, $class);

    return $self;

}

# Method: priority
#
#	Return select options for the priority field 
#
# Returns:
#
#	Array ref containing hash ref with value, printable
#	value and selected status
#
sub priority
{

    my  @options;

    foreach my $i (qw(0 1 2 3 4 5 6 7)) {
        push (@options, {
                value => $i,
                printableValue => $i
                }
             );
    }

    return \@options;

}

# Method: warnOnChangeOnId
#
# Overrides:
#
#       <EBox::Model::DataTable::warnOnChangeOnId>
#
sub warnOnChangeOnId
{

    my ($self, %params) = @_;

    my ($modelName, $id, $changedData, $oldRow) = ( $params{modelName},
            $params{id},
            $params{changedData},
            $params{oldRow} );

    my $strToShow = __x('Change or remove some rules on {contextName}',
            contextName => $self->printableContextName());

    if ( $modelName =~ m/GatewayTable/ ) {
        if ( exists $changedData->{interface} ) {
            my $oldGatewayIface = $oldRow->valueByName('interface');
            if ( ($oldGatewayIface eq $self->{interface}) &&
                    ($self->size() > 0) ) {
                return $strToShow;
            }
        } else {
            if ( $self->isUsingId($modelName, $id) ) {
                if ( exists $changedData->{upload} ) {
                    return $strToShow;
                }
                if ( exists $changedData->{download} ) {
                    return $strToShow;
                }
            }
        }
    }

    return '';

}

# Method: isUsingId
#
# Overrides:
#
#       <EBox::Model::DataTable::isUsingId>
#
sub isUsingId
{

    my ($self, $modelName, $id) = @_;

    if ( $modelName eq 'GatewayTable' ) {
        if ( $self->{interfaceType} eq 'external' ) {
            my $manager = EBox::Model::ModelManager->instance();
            my $observableModel = $manager->model($modelName);

            my $gateway = $observableModel->row($id);
            my $gatewayIface = $gateway->valueByName('interface');
            return ($gatewayIface eq $self->{interface}) && ($self->size() > 0);
        } else {
            # Every time a gateway is changed, 
            # call a warning from an internal interface
            return ($self->size() > 0);
        }
    }

    return 0;

}

# Method: notifyForeignModelAction
#
#      Called whenever an action is performed on a gateway whose
#      interface is the one we are shaping
#
# Overrides:
#
#      <EBox::Model::DataTable::notifyForeignModelAction>
#
sub notifyForeignModelAction
{

    my ($self, $modelName, $action, $row) = @_;

    my $userNotes = '';
    if ( $action eq 'add' ) {
        # Do nothing, it is also better
        return $userNotes;
    } elsif ( $action eq 'del' or
              $action eq 'update') {

        if ( $row->valueByName('interface') eq $self->{interface} ) {
            # Check new bandwidth
            my $netMod = EBox::Global->modInstance('network');
            my $limitRate;
            if ( $self->{interfaceType} eq 'external' ) {
                $limitRate = $self->{ts}->uploadRate($self->{interface});
            } else {
                # Internal interface
                $limitRate = $self->{ts}->totalDownloadRate();
            }
            if ( $limitRate == 0 or (not $self->{ts}->enoughInterfaces())) {
                $userNotes = $self->_removeRules();
            } else {
                $userNotes = $self->_normalize($self->_stateRate(), $limitRate);
            }
            $self->_setStateRate( $limitRate );
        } else {
            # Check if there are any download rate
            if ( $self->{ts}->totalDownloadRate() == 0) {
                # Remove our rules anyway
                $userNotes = $self->_removeRules();
            }
        }
    }
        return $userNotes;

}

# Method: index
#
# Overrides:
#
#     <EBox::Model::DataTable::index>
#
sub index
{

    my ($self) = @_;

    return $self->{interface};

}

# Method: printableIndex
#
# Overrides:
#
#     <EBox::Model::DataTable::printableIndex>
#
sub printableIndex
{

    my ($self) = @_;

    if ( $self->{interfaceType} eq 'internal' ) {
        return __x('{iface} (internal interface)',
                iface => $self->{interface});
    } else {
        return __x('{iface} (external interface)',
                iface => $self->{interface});
    }

}


# Method: validateTypedRow
#
# Overrides:
#
#       <EBox::Model::DataTable::validateTypedRow>
#
# Exceptions:
#
#       <EBox::Exceptions::External> - throw if interface is not
#       external or the rule cannot be built
#
#       <EBox::Exceptions::InvalidData> - throw if parameter has
#       invalid data
#
sub validateTypedRow
{
    my ($self, $action, $params) = @_;

    if ( defined ( $params->{guaranteed_rate} )) {
        $self->_checkRate( $params->{guaranteed_rate},
                __('Guaranteed rate'));
    }

    if ( defined ( $params->{limited_rate} )) {
        $self->_checkRate( $params->{limited_rate},
                __('Limited rate'));
    }

    # Check objects have members
    my $objMod = EBox::Global->modInstance('objects');
    foreach my $target (qw(source destination)) {
        if ( defined ( $params->{$target} )) {
            if ( $params->{$target}->subtype()->isa('EBox::Types::Select') ) {
                my $srcObjId = $params->{$target}->value();
                unless ( @{$objMod->objectAddresses($srcObjId)} > 0 ) {
                    throw EBox::Exceptions::External(
                    __x('Object {object} has no members. Please add at ' .
                        'least one to add rules using this object',
                        object => $params->{$target}->printableValue()));
                }
            }
        }
    }

    if ( $action eq 'update' ) {
        # Fill those parameters which haven't been changed
        my $oldRow = $self->row($params->{id});
        foreach my $paramName (keys %{$oldRow->hashElements()}) {
            unless ( defined ( $params->{$paramName})) {
                $params->{$paramName} = $oldRow->elementByName($paramName);
            }
        }
    }

    my $service = $params->{service}->subtype();
    if ($service->fieldName() eq 'port') {
        my $servMod = EBox::Global->modInstance('services');
        # Check if service is any, any source or destination is given
        if ($service->value() eq 'any' 
           and $params->{source}->subtype()->isa('EBox::Types::Union::Text') 
           and $params->{destination}->subtype()->isa('EBox::Types::Union::Text')) {
            
            throw EBox::Exceptions::External(
                __('If service is any, some source or' .
                   'destination should be provided'));

        }
    }
    # Transform objects (Select type) to object identifier to satisfy
    # checkRule API
    my %targets;
    foreach my $target (qw(source destination)) {
        if ( $params->{$target}->subtype()->isa('EBox::Types::Select') ) {
            $targets{$target} = $params->{$target}->value();
        } else {
            $targets{$target} = $params->{$target}->subtype();
        }
    }

    # Check the memory structure works as well
    $self->{ts}->checkRule(interface      => $self->{interface},
            service        => $params->{service}->value(),
            source         => $targets{source},
            destination    => $targets{destination},
            priority       => $params->{priority}->value(),
            guaranteedRate => $params->{guaranteed_rate}->value(),
            limitedRate    => $params->{limited_rate}->value(),
            ruleId         => $params->{id}, # undef on addition
            enabled        => $params->{enabled},
            );

}


# Method: addedRowNotify
#
#	Call whenever a row is added. We should add the rule
#       to the interface in dynamic structure
#
# Arguments:
#
#       row - hash ref with all the fields rows and their values
#
#
sub addedRowNotify
  {

#    my ($self, $row_ref) = @_;
#
#    my $guaranteedRate = $row_ref->{valueHash}->{'guaranteed_rate'}->value();
#    my $limitedRate = $row_ref->{valueHash}->{'limited_rate'}->value();
##    my $enabled        = $row_ref->{valueHash}->{enabled}->value();
#
#    # Get priority from order
#    my $priority = $row_ref->{priority};
#
#    # Now addRule doesn't need any argument since it's already done by model
#
#    $self->{ts}->addRule(
#			 interface      => $self->{interface},
#			 guaranteedRate => $guaranteedRate,
#			 limitedRate    => $limitedRate,
#			 enabled        => 'enabled',
#			);
#
  }

# Method: deletedRowNotify
#
#        See <EBox::Model::DataTable::deletedRowNotify>
#
sub deletedRowNotify
  {

#    my ($self, $row_ref, $force) = @_;
#
#    unless ( $force ) {
#        $self->{ts}->removeRule(
#                                interface      => $self->{interface},
#                               );
#    }

  }

# Method: updatedRowNotify
#
#        See <EBox::Model::DataTable::updatedRowNotify>
#
sub updatedRowNotify
  {

    my ($self, $row_ref, $force) = @_;

#    unless ( $force ) {
#        my $ruleId = $row_ref->{id};
#        $self->{ts}->updateRule( interface      => $self->{interface},
#                                 ruleId         => $ruleId,
#                               );
#    }

  }

# Method: committedLimitRate
#
#       Get the limit rate to use to build the tree at this moment
#
# Returns:
#
#       Int - the current state for limit rate for this interface at
#       traffic shaping module
#
sub committedLimitRate
{
    my ($self) = @_;

    return $self->_stateRate();

}

# Group: Protected methods

# Method: _table
#
#	Describe the traffic shaping table
#
# Returns:
#
# 	hash ref - table's description
#
sub _table
{

    my ($self) = @_;

    my @tableHead =
        (
         new EBox::Types::Union(
            fieldName   => 'service',
            printableName => __('Service'),
            subtypes =>
               [
                new EBox::Types::Select(
                    fieldName       => 'service_port',
                    printableName   => __('Port based service'),
                    foreignModel    => \&_serviceModel,
                    foreignField    => 'name',
                    editable        => 1,
                    ),
                new EBox::Types::Select(
                    fieldName       => 'service_l7Protocol',
                    printableName   => __('Application based service'),
                    foreignModel    => \&_l7Protocol,
                    foreignField    => 'protocol',
                    editable        => 1,
                    ),
                new EBox::Types::Select(
                    fieldName       => 'service_l7Group',
                    printableName   => __('Application based service group'),
                    foreignModel    => \&_l7Group,
                    foreignField    => 'group',
                    editable        => 1,
                    ),
                ],
             editable => 1,
             help => _serviceHelp()
             ),
         new EBox::Types::Union(
             fieldName     => 'source',
             printableName => __('Source'),
             subtypes      =>
                [
                 new EBox::Types::Union::Text(
                     'fieldName' => 'source_any',
                     'printableName' => __('Any')),
                 new EBox::Types::IPAddr(
                     fieldName     => 'source_ipaddr',
                     printableName => __('Source IP'),
                     editable      => 1,
                     ),
                 new EBox::Types::MACAddr(
                     fieldName     => 'source_macaddr',
                     printableName => __('Source MAC'),
                     editable      => 1,
                     ),
                 new EBox::Types::Select(
                     fieldName     => 'source_object',
                     printableName => __('Source object'),
                     editable      => 1,
                     foreignModel => \&_objectModel,
                     foreignField => 'name'
                     )
                 ],
             editable => 1,
             ),
         new EBox::Types::Union(
             fieldName     => 'destination',
             printableName => __('Destination'),
             subtypes      =>
                 [
                 new EBox::Types::Union::Text(
                     'fieldName' => 'destination_any',
                     'printableName' => __('Any')),
                 new EBox::Types::IPAddr(
                     fieldName     => 'destination_ipaddr',
                     printableName => __('Destination IP'),
                     editable      => 1,
                     ),
                 new EBox::Types::Select(
                     fieldName     => 'destination_object',
                     printableName => __('Destination object'),
                     type          => 'select',
                     foreignModel => \&_objectModel,
                     foreignField => 'name',
                     editable      => 1 ),
                 ],
              editable => 1,
              ),
         new EBox::Types::Select(
             fieldName     => 'priority',
             printableName => __('Priority'),
             editable      => 1,
             populate      => \&priority,
             defaultValue  => 7,
             help          => __('Lowest priotiry: 7 Highest priority: 0')
             ),
         new EBox::Types::Int(
             fieldName     => 'guaranteed_rate',
             printableName => __('Guaranteed Rate'),
             size          => 3,
             editable      => 1, # editable
             trailingText  => __('Kbit/s'),
             defaultValue  => 0,
             help          => __('Note that  ' .
                 'The sum of all guaranteed ' .
                 'rates cannot exceed your ' .
                 'total bandwidth. 0 means unlimited rate.')
              ),
         new EBox::Types::Int(
                 fieldName     => 'limited_rate',
                 printableName => __('Limited Rate'),
                 class         => 'tcenter',
                 type          => 'int',
                 size          => 3,
                 editable      => 1, # editable
                 trailingText  => __('Kbit/s'),
                 defaultValue  => 0,
                 help          => __('Traffic will not exceed ' .
                     'this rate. 0 means unlimited rate.')
              ),
      );


    my $dataTable = { 
        'tableName'          => 'tsTable',
        'printableTableName' => __x('Rules list for {printableIndex}',
                                    printableIndex => $self->printableIndex()),
        'defaultActions'     =>
            [ 'add', 'del', 'editField', 'changeView', 'move' ],
        'modelDomain'        => 'TrafficShaping',
        'tableDescription'   => \@tableHead,
        'class'              => 'dataTable',
        # Priority field set the ordering through _order function
        'order'              => 1,
        'help'               => __('Note that if the interface is internal, ' .
                                   'the traffic flow comes from Internet to ' .
                                   'inside and the external is the other way '.
                                   'around'),
        'rowUnique'          => 1,  # Set each row is unique
        'printableRowName'   => __('rule'),
        'notifyActions'      => [ 'GatewayTable' ],
        'automaticRemove' => 1,    # Related to objects,
                                   # remove rules with an
                                   # object when that
                                   # object is being
                                   # deleted
        'enableProperty'      => 1, # The rules can be enabled or not
        'defaultEnabledValue' => 1, # The rule is enabled by default
    };

    return $dataTable;

}

####################################################
# Group: Private methods
####################################################


# Get the object model from Objects module
sub _objectModel
{
    return EBox::Global->modInstance('objects')->{objectModel};
}

# Get the object model from Service module
sub _serviceModel
{
    return EBox::Global->modInstance('services')->{serviceModel};
}

# Get the object model from l7-protocol
sub _l7Protocol 
{

    return EBox::Global->modInstance('l7-protocols')->model('Protocols');
}

# Get the object model from l7-groups
sub _l7Group
{

    return EBox::Global->modInstance('l7-protocols')->model('Groups');
}


# Remove every rule from the model since no limit rate are possible
sub _removeRules
{

    my ($self) = @_;

    my $rows = $self->rows();

    foreach my $row (@{$rows}) {
        $self->removeRow( $row->{id}, 1);
    }

    my $msg = '';
    my $numRows = scalar(@{$rows});
    if ($numRows > 0) {
        $msg = __x('Remove {num} rules at {modelName}',
               num => $numRows,
               modelName => $self->printableContextName());
    }
    return $msg;
}

# Normalize the current rates (guaranteed and limited)
sub _normalize
{

    my ($self, $oldLimitRate, $currentLimitRate) = @_;

    my ($limitNum, $guaranNum, $removeNum) = (0, 0, 0);

    if ( $oldLimitRate > $currentLimitRate ) {
        # The bandwidth has been decreased
        for (my $pos = 0; $pos < $self->size(); $pos++ ) {
            my $row = $self->get( $pos );
            my $guaranteedRate = $row->valueByName('guaranteed_rate');
            my $limitedRate = $row->valueByName('limited_rate');
            if ( $limitedRate > $currentLimitRate ) {
                $limitedRate = $currentLimitRate;
                $limitNum++;
            }
            # Normalize guaranteed rate
            if ( $guaranteedRate != 0 ) {
                $guaranteedRate = ( $guaranteedRate * $currentLimitRate ) 
                                  / $oldLimitRate;
                $guaranNum++;
            }
            try {
                $self->set( $pos, guaranteed_rate => $guaranteedRate,
                        limited_rate => $limitedRate);
            } catch EBox::Exceptions::External with {
                # The updated rule is fucking everything up (min guaranteed
                # rate reached and more!)
                my ($exc) = @_;
                EBox::warn($row->id() . " is being removed. Reason: $exc");
                $self->removeRow( $row->id(), 1);
                $removeNum++;
                $pos--;
            }
        }
    }

    if ( $limitNum > 0 or $guaranNum > 0 ){
        return __x( 'Normalizing rates: {limitNum} rules have decreased its ' .
            'limit rate to {limitRate}, {guaranNum} rules have normalized ' . 
            'its guaranteed rate to maintain ' .
            'the same proportion that it has previously and {removeNum} ' .
            'have been deleted because its guaranteed rate was lower than ' .
            'the minimum allowed',
            limitNum => $limitNum, limitRate => $currentLimitRate,
            guaranNum => $guaranNum, removeNum => $removeNum);
    }

}

######################
# Checker methods
######################

# Check rate
# Throw InvalidData if it's not a positive number
sub _checkRate # (rate, printableName)
{

    my ($self, $rate, $printableName) = @_;

    if ( $rate->value() < 0 ) {
        throw EBox::Exceptions::InvalidData(
                'data'  => $printableName,
                'value' => $rate,
                );
    }

    return 1;

}

# Get the rate stored by state in order to work when gateway changes
# are produced
sub _stateRate
{
    my ($self) = @_;

    return $self->{gconfmodule}->st_get_int($self->{directory} . LIMIT_RATE_KEY);

}

# Set the rate into GConf state in order to work when gateway changes
# are produced
sub _setStateRate
{
    my ($self, $rate) = @_;

    $self->{gconfmodule}->st_set_int($self->{directory} . LIMIT_RATE_KEY,
            $rate);

}

sub _serviceHelp
{
    return __('Port based protocols use the port number to match a service, ' .
              'while Application based protocols are slower but more ' .
              'effective as they check the content of any ' .
              'packet to match a service.');

              
}
1;
