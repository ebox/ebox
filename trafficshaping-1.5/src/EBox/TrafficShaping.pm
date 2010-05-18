# Copyright (C) 2006,2007 Warp Networks S.L.
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

# FIXME:  Get rid of unnecessary stuff already provided by the framework
#

# Class: EBox::TrafficShaping
#
#      This eBox module is intended to manage traffic shaping rules
#      set by user per real interface. Each rule may represent a bunch
#      of iptables and tc commands to tell the kernel how to manage
#      the traffic flows.
#
#      Current state of developing is the following:
#
#      Shaping (guaranteed, limited and prioriting) traffic per
#      service (protocol/port union), source (IP, MAC, object) and
#      destination (IP, object) on *egress* traffic from every static
#      interface
#
package EBox::TrafficShaping;

use strict;
use warnings;

use base qw(EBox::Module::Service
            EBox::NetworkObserver
            EBox::Model::ModelProvider
            EBox::Model::CompositeProvider
            );

######################################
# Dependencies:
# Perl6::Junction package
######################################
use Perl6::Junction qw( any );

use EBox::Gettext;

use EBox::Global;
use EBox::Validate qw( checkProtocol checkPort );
use EBox::LogAdmin qw ( :all );

# Used exceptions
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::MissingArgument;
# Command wrappers
use EBox::TC;
use EBox::Iptables;

# Concrete builders
use EBox::TrafficShaping::TreeBuilder::Default;
use EBox::TrafficShaping::TreeBuilder::HTB;

# Rule model
use EBox::TrafficShaping::Model::RuleTable;
use EBox::TrafficShaping::Model::InterfaceRate;

# Model managers
use EBox::Model::ModelManager;
use EBox::Model::CompositeManager;

# Dependencies
use Error qw(:try);
use List::Util;
use Perl6::Junction qw(none);

# Using the brand new eBox types
use EBox::Types::IPAddr;
use EBox::Types::MACAddr;

# We set rule identifiers among 0100 and FF00
use constant MIN_ID_VALUE => 256; # 0x100
use constant MAX_ID_VALUE => 65280; # 0xFF00
use constant MAX_RULE_NUM => 256; # FF rules
use constant DEFAULT_CLASS_ID => 21;

# Constructor for traffic shaping module
sub _create
  {
    my $class = shift;
    my $self = $class->SUPER::_create(name   => 'trafficshaping',
				      domain => 'ebox-trafficshaping',
                      printableName => __n('Traffic Shaping'),
				      @_);

    $self->{network} = EBox::Global->modInstance('network');
    $self->{objects} = EBox::Global->modInstance('objects');

#    $self->_setLogAdminActions();

    bless($self, $class);

    return $self;
  }

# FIXME
sub startUp
{
     my ($self) = @_;
     # Create rule models
     #$self->_createRuleModels();

    # Create wrappers
    $self->{tc} = EBox::TC->new();
    $self->{ipTables} = EBox::Iptables->new();
    # Create tree builders
    $self->_createBuilders(regenConfig => 0);

    $self->{'started'} = 1;
}


# Method: actions
#
# 	Override EBox::Module::Service::actions
#
sub actions
{
    return [
	{
            'action' => __('Add iptables rules to mangle table'),
            'reason' => __('To mark packets with different priorities and rates'),
            'module' => 'trafficshaping'
	},
        {
            'action' => __('Add tc rules'),
            'reason' => __('To implement the traffic shaping rules'),
            'module' => 'trafficshaping'
	}
       ];
}

# Method: isRunning
#
# Overrides:
#
#       <EBox::ServiceModule::ServiceInterface::isRunning>
#
sub isRunning
{
    my ($self) = @_;
    return $self->isEnabled();
}

# Method: _enforceServiceState
#
# Overrides:
#
#       <EBox::Module::Service::_enforceServiceState>
#
sub _enforceServiceState
{

    my ($self) = @_;

    # FIXME
    # Clean up stuff
    $self->_stopService();
    return unless ($self->isEnabled());

    # Create builders ( Disc -> Memory ) Mandatory every time an
    # access in memory is done
    $self->_createBuilders(regenConfig => 1);

    # Called every time a Save Changes is done
    my $ifaces_ref = $self->_configuredInterfaces();
    # Build a tree for each interface

    $self->_createPostroutingChain();

    $self->_resetInterfacesChains();

    foreach my $iface (@{$ifaces_ref}) {
        if ( defined ( $self->{builders}->{$iface} ) ) {
            # Dump tc and iptables commands
            my $tcCommands_ref = $self->{builders}->{$iface}->dumpTcCommands();
            my $ipTablesCommands_ref = $self->{builders}->{$iface}->dumpIptablesCommands();
            # Execute tc commands
            $self->{tc}->reset($iface);            # First, deleting everything was there
            $self->{tc}->execute($tcCommands_ref); # Second, execute them!
            # Execute iptables commands
            $self->_executeIptablesCmds($ipTablesCommands_ref);
        }
    }
}


sub _resetInterfacesChains
{
    my ($self) = @_;

    my $interfaces;
    if (l7FilterEnabled()) {
        # due to app protocols we must reset all chains bz a rule with app protocol
        # requires ruels in all interfaces
         my $network = EBox::Global->modInstance('network');
        $interfaces = $self->_realIfaces();
    } else {
      $interfaces =  $self->_configuredInterfaces();
    }

    foreach my $iface (@{$interfaces  }) {
            $self->_resetChain($iface);
    }
}

# Method: models
#
# Overrides:
#
#       <EBox::Model::ModelProvider::models>
#
sub models
{

    my ($self) = @_;

    my $netMod = $self->{'network'};

    my @currentModels = ($self->interfaceRateModel());
    my @extIfaces = @{$netMod->ExternalIfaces()};
    my @intIfaces = @{$netMod->InternalIfaces()};

    my @availableIfaces = ();

    foreach my $iface (@extIfaces) {
        if ( $self->uploadRate($iface) > 0) {
            push (@availableIfaces, $iface);
        }
    }

    push( @availableIfaces, @intIfaces);

    foreach my $iface ( @availableIfaces ) {
        push ( @currentModels, $self->ruleModel($netMod->realIface($iface)));
    }


    return \@currentModels;

}

# Method: reloadModelsOnChange
#
# Overrides:
#
#     <EBox::Model::ModelProvider::reloadModelsOnChange>
#
sub reloadModelsOnChange
{

    return [ 'InterfaceRate' ];

}

# Method: _exposedMethods
#
# Overrides:
#
#    <EBox::Model::DataTable::_exposedMethods>
#
sub _exposedMethods
{

  my %exposedMethods =
    ( addRule    => { action     => 'add',
                      path       => [ 'tsTable' ],
                    },
      removeRule => { action     => 'del',
                      path       => [ 'tsTable' ],
                    },
      enableRule => { action     => 'set',
                      path       => [ 'tsTable' ],
                      selector   => [ 'enabled' ],
		     },
      isEnabledRule => { action   => 'get',
                         path     => [ 'tsTable' ],
                         selector => [ 'enabled' ],
                       },
      updateRule => { action     => 'set',
                      path       => [ 'tsTable' ],
                    },
      getRule    => { action     => 'get',
                      path       => [ 'tsTable' ],
                      selector   => [ 'id' ],
                    },
    );

  return \%exposedMethods;

}

# Method: compositeClasses
#
# Overrides:
#
#     <EBox::Model::CompositeProvider::compositeClasses>
#
sub compositeClasses
{

    return [
            'EBox::TrafficShaping::Composite::DynamicGeneral'
           ];

}

# Method: reloadCompositesOnChange
#
# Overrides:
#
#     <EBox::Model::CompositeProvider::reloadCompositesOnChange>
#
sub reloadCompositesOnChange
{

    return [ 'InterfaceRate' ];

}

# Method: _stopService
#
#     Call every time the module is stopped
#
# Overrides:
#
#     <EBox::Module::_stopService>
#
sub _stopService
  {
    my $self = shift;

    $self->startUp() unless ($self->{'started'});

    my $ifaces_ref = $self->_configuredInterfaces();

    $self->_deletePostroutingChain();
    foreach my $iface (@{$ifaces_ref}) {
      # Cleaning iptables
      $self->_deleteChains($iface);
      # Cleaning tc
      $self->{tc}->reset($iface);
    }
  }


# Method: summary
#
sub summary
  {
  }

# Method: menu
#
#       Add Traffic Shaping module to eBox menu
#
# Parameters:
#
#       root - the <EBox::Menu::Root> where to leave our items
#
sub menu # (root)
{

    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder('name' => 'TrafficShaping',
                                        'text' => $self->printableName(),
                                        'separator' => 'Gateway',
                                        'order' => 220);
    $folder->add(new EBox::Menu::Item('url'  => 'TrafficShaping/Composite/DynamicGeneral',
                                      'text' => __('Rules')));
    $folder->add(new EBox::Menu::Item('url'  => 'TrafficShaping/View/InterfaceRate',
                                      'text' => __('Interface Rates')));

    $root->add($folder);
}

# Method: checkRule
#
#       Check if the rule passed can be added or updated. The guaranteed rate
#       or the limited rate should be given.
#
# Parameters:
#
#       interface      - interface under the rule is given
#
#       service - String the service identifier stored at
#       ebox-services module containing the inet protocol and source
#       and destination port numbers *(Optional)*
#
#       source - the rule source. It could be an
#       <EBox::Types::IPAddr>, <EBox::Types::MACAddr>, an object
#       identifier (more info at <EBox::Objects>) or an
#       <EBox::Types::Union::Text> to indicate any source *(Optional)*
#
#       destination - the rule destination. It could be an
#       <EBox::Types::IPAddr>, an object identifier (more info at
#       <EBox::Objects>) or an <EBox::Types::Union::Text> to indicate
#       any destination *(Optional)*
#
#       priority       - Int the rule priority *(Optional)*
#                        Default value: Lowest priority
#       guaranteedRate - maximum guaranteed rate in Kilobits per second *(Optional)*
#       limitedRate    - maximum allowed rate in Kilobits per second *(Optional)*
#       ruleId         - the rule identifier. It's given if the rule is
#                        gonna be updated *(Optional)*
#
#       enabled        - Boolean indicating whether the rule is enabled or not
#
# Returns:
#
#       true - if the rule can be added (updated) without problems
#
# Exceptions:
#
#      <EBox::Exceptions::MissingArgument> - throw if parameter is not
#      passed
#      <EBox::Exceptions::InvalidData> - throw if parameter has invalid
#      data
#      <EBox::Exceptions::External> - throw if interface is not external
#       or the rule cannot be built
#
sub checkRule
  {

    my ($self, %ruleParams) = @_;

    throw EBox::Exceptions::MissingArgument( __('Interface') )
      unless defined( $ruleParams{interface} );

    # Setting standard rates if not defined
    $ruleParams{guaranteedRate} = 0 unless defined ( $ruleParams{guaranteedRate} );
    $ruleParams{guaranteedRate} = 0 if $ruleParams{guaranteedRate} eq '';
    $ruleParams{limitedRate} = 0 unless defined ( $ruleParams{limitedRate} );
    $ruleParams{limitedRate} = 0 if $ruleParams{limitedRate} eq '';

    # Check rule availability
    my @ruleModels = grep {$_->name() eq 'tsTable' } @{$self->models()};
    my $nRules     = List::Util::sum(map { scalar(@{$_->ids()}) } @ruleModels);
    if ( $nRules >= MAX_RULE_NUM and (not defined ($ruleParams{ruleId}))) {
      throw EBox::Exceptions::External(
            __x('The maximum rule account {max} is reached, ' .
		'please delete at least one in order to to add a new one',
		max => MAX_RULE_NUM));
    }

    unless ( defined ( $ruleParams{priority} )) {
      # Set the priority the lowest
      $ruleParams{priority} = 7;
    }

    # Create builders ( Disc -> Memory ) Mandatory every time an
    # access in memory is done
    $self->_createBuilders(regenConfig => 0);

    if ( defined( $ruleParams{ruleId} )) {
      # Try to update the rule
      $self->_updateRule( $ruleParams{interface}, $ruleParams{ruleId}, \%ruleParams, 'test' );
    }
    else {
      # Try to build the rule
      $self->_buildRule( $ruleParams{interface}, \%ruleParams, 'test');
    }

    # If it works correctly, the write to gconf is done afterwards by
    # TrafficShapingModel

    return 1;

  }

# Method: listRules
#
#       Send a list with all the rules within an interface
#
# Parameters:
#
#       interface - the interface name
#
# Returns
#
#       array ref - containing hash references which have the
#       following attributes:
#         - service - String the service identifier
#         - source  - the selected source. It can be one of the following:
#                     - <EBox::Types::IPAddr>
#                     - <EBox::Types::MACAddr>
#                     - String containing the source object
#         - destination - the selected destination. It can be one of the following:
#                     - <EBox::Types::IPAddr>
#                     - String containing the destination object
#         - guaranteed_rate - maximum guaranteed rate
#         - limited_rate    - maximum traffic rate
#         - priority        - priority (lower number, highest priority)
#         - enabled         - is this rule enabled?
#         - ruleId          - unique identifier for this rule
#
sub listRules
{
    my ($self, $iface) = @_;

    my $ruleModel = $self->ruleModel($iface);

    my @rules = ();
    foreach my $id (@{$ruleModel->ids()}) {
        my $row = $ruleModel->row($id);
        my $ruleRef =
          {
           ruleId      => $id,
           service     => $row->elementByName('service'),
           source      => $row->elementByName('source')->subtype(),
           destination => $row->elementByName('destination')->subtype(),
           priority    => $row->valueByName('priority'),
           guaranteed_rate => $row->valueByName('guaranteed_rate'),
           limited_rate => $row->valueByName('limited_rate'),
           enabled     => $row->valueByName('enabled'),
          };
        push ( @rules, $ruleRef );
    }

    return \@rules;

  }

# Method: getLowestPriority
#
#       Accessor to the lowest priority rule for an interface. If none
#       is found, the lowest priority is zero.
#
# Parameters:
#
#       interface - interface name
#       search    - search a new lowest priority (Optional)
#
# Returns:
#
#       Integer - the lowest priority (the highest number)
#
sub getLowestPriority # (interface, search?)
  {

    my ($self, $iface, $search) = @_;

    if ( $search or
         not defined( $self->{lowestPriority} )) {
      $self->_setNewLowestPriority($iface);
    }

    return $self->{lowestPriority};

  }

# Method: ruleModel
#
#       Return the model associated to the rules table
#
# Parameters:
#
#       interface - String interface attached to the rule table model
#
# Returns:
#
#       <EBox::TrafficShaping::Model::RuleTable> - if there is a model
#       associated with the given interface
#
#       undef - if there is no model associated with the given
#       interface
#
# Exceptions:
#
#      <EBox::Exceptions::MissingArgument> - throw if parameter is not
#      passed
#

sub ruleModel # (iface)
{

    my ($self, $iface) = @_;

    throw EBox::Exceptions::MissingArgument( __('Interface') )
      unless defined( $iface );

    if ( not defined ($self->{ruleModels}->{$iface})) {
        try {
            $self->_checkInterface($iface);
            # Create the rule model if it's not already created
            $self->{ruleModels}->{$iface}
              = new EBox::TrafficShaping::Model::RuleTable(
                                                           'gconfmodule' => $self,
                                                           'directory'   => "$iface/user_rules",
                                                           'tablename'   => 'rule',
                                                           'interface'   => $iface,
                                                          );
        } catch EBox::Exceptions::External with {
            # If the interface cannot be shaped, then return undef
            ;
        };
    }

    return $self->{ruleModels}->{$iface};

}

# Method:   interfaceRateModel 
#
#   Returns a <EBox::TrafficShaping::Model::InterfaceRate> model
#
# Returns:
#
#       <EBox::TrafficShaping::Model::InterfaceRate>
#
sub interfaceRateModel
{
    my ($self) = @_;

    if ( not defined ($self->{rateModel})) {
        $self->{rateModel}
            = new EBox::TrafficShaping::Model::InterfaceRate(
                gconfmodule => $self,
                directory   => 'InterfaceRate',
                tablename   => 'InterfaceRate',
        );
    };

    return $self->{rateModel};
}

# Method: ShaperChain
#
#      Class method which returns the iptables chain used by Traffic
#      Shaping module
#
# Parameters:
#
#      iface - String with the interface where the traffic flows
#      where - from where it's shaper (Options: egress, ingress, forward)
#              *(Optional)* Default value: egress
#
# Returns:
#
#      String - shaper chain's name
#
sub ShaperChain
{

    my ($class, $iface, $where) = @_;

    $where = 'egress' unless defined ( $where );

    if ( $where eq 'egress' ) {
        return 'EBOX-SHAPER-OUT-' . $iface;
    } elsif ( $where eq 'ingress' ) {
        return 'EBOX-SHAPER-IN-' . $iface;
    }

}

# Method: MaxIdValue
#
#      Get the maximum identifier value allowed by the system
#
# Returns:
#
#      Int - the maximum allowed identifier
#
sub MaxIdValue
{
    return MAX_ID_VALUE;
}

###################################
# Network Observer Implementation
###################################

# Method: ifaceMethodChanged
#
# Implements:
#
#     <EBox::NetworkObserver::ifaceMethodChanged>
#
# Returns:
#
#     true - if there are rules on the model associated to the
#     given interface
#
#     false - otherwise
#
sub ifaceMethodChanged
  {

      my ($self, $iface, $oldMethod, $newMethod) = @_;

      my @others = qw(notset trunk);
      if ( grep { $_ eq $oldMethod } @others
           and (grep { $_ ne $newMethod } @others )) {
          return 1 unless ( $self->{network}->ifaceIsExternal($iface));
      } elsif ( grep { $_ eq $newMethod } @others
                and (grep { $_ ne $oldMethod } @others )) {
          return 1;
      } elsif ( $newMethod eq 'dhcp'
               and $oldMethod eq 'static' ) {
          return 1 if ( $self->{network}->ifaceIsExternal($iface));
      }
      return 0;

  }

# Method: ifaceMethodChangeDone
#
# Implements:
#
#     <EBox::NetworkObserver::ifaceMethodChangeDone>
#
sub ifaceMethodChangeDone
{
    my ($self) = @_;
    my $manager = EBox::Model::ModelManager->instance();
    # Mark manager as changed and force a resetup of the
    # models by asking for InterfaceRate
    $manager->markAsChanged();
    $manager->model('trafficshaping/InterfaceRate');
}


# Method: ifaceExternalChanged
#
# Implements:
#
#    <EBox::NetworkObserver::ifaceExternalChanged>.
#
# Returns:
#
#    true - if there are rules on the model associated to the given
#    interface or the change provokes not enough interfaces to shape
#    the traffic
#
#    false - otherwise
#
sub ifaceExternalChanged # (iface, external)
{

    my ($self, $iface, $external) = @_;

    # XXX Disabled until network observers work properly.
    #     We need to be notified when there's a change
    #     from external to internal, not only  interntal
    #     to external
    return 0;

    # Check if any interface is being shaped
    # if ( defined ( $self->{ruleModels}->{$iface} )) {
    #    return not $self->enoughInterfaces();
    # }
    # return 0;

}

# Method: changeIfaceExternalProperty
#
#    Remove every rule associated to the given interface
#
# Implements:
#
#    <EBox::NetworkObserver::changeIfaceExternalProperty>
#
sub changeIfaceExternalProperty # (iface, external)
{

    my ($self, $iface, $external) = @_;

    my $manager = EBox::Model::ModelManager->instance();
    $manager->markAsChanged();

}


# Method: freeIface
#
#        See <EBox::NetworkObserver::freeIface>.
#
# Parameters:
#
#       iface - interface name
#
# Returns:
#
#       boolean -
#
sub freeIface # (iface)
{

    my ($self, $iface) = @_;

    $self->_deleteIface($iface);
    my $manager = EBox::Model::ModelManager->instance();
    $manager->markAsChanged();
    $manager = EBox::Model::CompositeManager->Instance();
    $manager->markAsChanged();

}

###
# Workaround related to upload rate from an external interface
###

# Method: uploadRate
#
#    Get the upload rate from an interface in kilobits per second
#
# Parameters:
#
#    iface - String interface's name
#
# Returns:
#
#    Int - the upload rate in kilobits per second
#
#    0 - if the interface is an internal one
#
sub uploadRate # (iface)
{
    my ($self, $iface) = @_;

    my $rates = $self->interfaceRateModel();
    my $row = $rates->findRow(
        interface => $self->{network}->etherIface($iface)
    );

    return 0 unless defined($row);

    return $row->valueByName('upload');
}

# Method: totalDownloadRate
#
#        Get the total download rate from the external interfaces in
#        kilobits per second
#
# Returns:
#
#        Int - the download rate in kilobits per second
#
sub totalDownloadRate
{

# FIXME: Change when the ticket #373

    my ($self) = @_;

    my $sumDownload = 0;
    my $rates = $self->interfaceRateModel();
    foreach my $iface (@{$rates->ids()}) {
        $sumDownload += $rates->row($iface)->valueByName('download');
    }

    return $sumDownload;
}

# Method: enoughInterfaces
#
#      Return if there are enough interfaces to do traffic shaping
#
sub enoughInterfaces
{

    my ($self) = @_;

    my $netMod = $self->{network};

    my @extIfaces = @{$netMod->ExternalIfaces()};
    my @intIfaces = @{$netMod->InternalIfaces()};

    return ( @extIfaces > 0 ) && (@intIfaces > 0);

}

###################################
# Group: Private Methods
###################################

###
# Priority helper methods
###

# Set the new lowest priority after one is out within an interface
# If priority is given, it just checks with the currently lowest
# priority
sub _setNewLowestPriority # (iface, priority?)
  {

    my ($self, $iface, $priority) = @_;

    if ( defined( $priority ) ){
      # Check only with the currently lowest priority
      if ( $priority > $self->getLowestPriority($iface) ){
	$self->_setLowestPriority($iface, $priority);
      }
    }
    else {
      # Check all priority entries from within given interface
      my $ruleDir = $self->_ruleDirectory($iface);

      my $dirs_ref = $self->array_from_dir($ruleDir);

      # Search for the lowest at array
      my $lowest = 0;
      foreach my $rule_ref (@{$dirs_ref}) {
	$lowest = $rule_ref->{priority} if ( $rule_ref->{priority} > $lowest );
      }
      # Set lowest
      $self->_setLowestPriority($iface, $lowest);
    }

  }

# Method: _setLowestPriority
#
#       Mutator to the lowest priority.
#
# Parameters:
#
#       interface - interface name
#       priority  - the lowest priority
#
sub _setLowestPriority # (interface, priority)
  {

    my ($self, $iface, $priority) = @_;

    $self->{lowestPriority} = $priority;
#    $self->set_int("$iface/user_rules/lowest_priority", $priority);

    return;

  }

###
# Rule model helper methods
###

# set every external interface to have a model
sub _createRuleModels
  {

    my ($self) = @_;

    my $global = EBox::Global->getInstance();
    my $network = $self->{'network'};

    my $ifaces_ref = $self->_realIfaces();
    foreach my $iface (@{$ifaces_ref}) {
      $self->{ruleModels}->{$iface} = new EBox::TrafficShaping::Model::RuleTable(
				    'gconfmodule' => $self,
				    'directory'   => "$iface/user_rules",
				    'tablename'   => 'rule',
				    'interface'   => $iface,
										);
    }

  }

# Delete those models which are not used
sub _deleteIface # (usedIfaces)
{
    my ($self, $iface) = @_;

    my $rateModel = $self->interfaceRateModel();
    my $row = $rateModel->findRow(interface => $iface);
    $rateModel->removeRow($row->id(), 1) if ($row);

    my $model = $self->{ruleModels}->{$iface};
    if ( defined ( $model )) {
        $model->removeAll(1);
        $self->{ruleModels}->{$iface} = undef;
    }
}

###
# Checker Functions
###

# Check interface existence and if it has gateways associated
# Throw External exception if not enough gateways to the external interface
# Throw DataNotFound if the interface doesn't exist
sub _checkInterface # (iface)
  {

    my ($self, $iface) = @_;

    my $global = EBox::Global->getInstance();
    my $network = $self->{'network'};
    $iface = $network->etherIface($iface);

    # Now shaping can be done at internal interfaces to egress traffic

    # If the interface doesn't exist, launch an DataNotFound exception
    if ( not $network->ifaceExists( $iface )) {
        throw EBox::Exceptions::DataNotFound( data => __('Interface'),
                value => $iface
                );
    }

    if ($network->ifaceMethod($iface) eq 'notset') {
        throw EBox::Exceptions::External("Iface not configured $iface");
    }

  }

# Check if there are rules are active within a given interface
# Returns true if any, false otherwise
sub _areRulesActive # (iface, countDisabled)
  {
    my ($self, $iface, $countDisabled) = @_;

    $countDisabled = 0 unless (defined($countDisabled));
    # Only check if there is a model
    my $model = $self->ruleModel($iface);

    if ( defined ($model) ) {
        if ( $countDisabled ) {
            return ($model->size() > 0);
        } else {
            my $enabledRows = $model->enabledRows();
            return (scalar(@{$enabledRows}) > 0);
        }
    } else {
        return 0;
    }

  }

###
# GConf related functions
###

# Given an interface and optionally a rule returns the directory
# within GConf
sub _ruleDirectory # (iface, ruleId?)
  {

    my ($self, $iface, $ruleId) = @_;

    my $dir = $self->ruleModel($iface)->directory() . '/keys';


    if ( defined ($ruleId) ) {
      return "$dir/$ruleId";
    }
    else {
      return $dir;
    }

  }

# Underlying stuff (Come to the mud)

# Method: _createTree
#
#       Creates a tree with the builder within an interface.
#
# Parameters:
#
#       interface - String interface's name to create the tree
#       type - String HTB, default or HFSC
#
# Exceptions:
#
#      <EBox::Exceptions::InvalidData> - throw if type is not one of
#      the supported
#
#      <EBox::Exceptions::MissingArgument> - throw if parameter is not
#      passed
#
#      <EBox::Exceptions::External> - throw if rate is not given for
#      every external interface
#
sub _createTree # (interface, type)
  {

    my ($self, $iface, $type) = @_;

    # Check arguments
    throw EBox::Exceptions::MissingArgument('interface')
      unless defined ( $iface );
    throw EBox::Exceptions::MissingArgument('type')
      unless defined ( $type );

    throw EBox::Exceptions::InvalidData(data => __('type'))
      unless ( $type eq any( qw(default HTB HFSC) ) );

    # Create builder
    if ( $type eq "default" ) {
      $self->{builders}->{$iface} = EBox::TrafficShaping::TreeBuilder::Default->new($iface);
      # Build it
      $self->{builders}->{$iface}->buildRoot();
    }
    elsif ( $type eq "HTB" ) {
      $self->{builders}->{$iface} = EBox::TrafficShaping::TreeBuilder::HTB->new($iface, $self);
      # Build it

      # Check if interface is internal or external to set a maximum
      # rate The maximum rate for an internal interface is the sum of
      # the download rate associated to the external interfaces

      # Get the rate from Network
      my $linkRate;
      my $model = $self->ruleModel($iface);
      $linkRate = $model->committedLimitRate();

      if ( not defined($linkRate) or $linkRate == 0) {
	throw EBox::Exceptions::External(__x("Interface {iface} should have a maximum " .
					     "bandwidth rate in order to do traffic shaping",
					     iface => $iface));
      }
      $self->{builders}->{$iface}->buildRoot(DEFAULT_CLASS_ID, $linkRate);
    }
    elsif ( $type eq "HFSC" ) {
      ;
    }

  }

# Build the tree from gconf variables stored.
# It assumes rules are correct
sub _buildGConfRules # (iface, regenConfig)
{

    my ($self, $iface, $regenConfig) = @_;

    my $model = $self->ruleModel($iface);

    my $rulesRef = [];

    foreach my $id (@{$model->ids()}) {
        my $row = $model->row($id);
        my $ruleRef = {};
        $ruleRef->{identifier} = $self->_nextMap($row->{id});
        $ruleRef->{service} = $row->elementByName('service');
        # Source and destination
        for my $targetName (qw(source destination)) {
            my $target = $row->elementByName($targetName)->subtype();
            if ( $target->isa('EBox::Types::Union::Text')) {
                $target = undef;
            } elsif ( $target->isa('EBox::Types::Select')) {
                # An object
                $target = $target->value();
            }
            $ruleRef->{$targetName}  = $target;
        }
        # Priority
        $ruleRef->{priority} = $row->valueByName('priority');

        # Rates
        # Transform from gconf to camelCase and set if they're null
        # since they're optional parameters
        $ruleRef->{guaranteedRate} = $row->valueByName('guaranteed_rate');
        $ruleRef->{guaranteedRate} = 0 unless defined ($ruleRef->{guaranteedRate});
        $ruleRef->{limitedRate} = $row->valueByName('limited_rate');
        $ruleRef->{limitedRate} = 0 unless defined ($ruleRef->{limitedRate});
        # Take care of enabled value only if regenConfig is enabled
        if ( $regenConfig ) {
            $ruleRef->{enabled} = $row->valueByName('enabled');
            $ruleRef->{enabled} = 1 unless defined ($ruleRef->{enabled});
        } else {
            $ruleRef->{enabled} = 1;
        }

        $self->_buildANewRule( $iface, $ruleRef, undef );

    }

}

# Create builders and they are stored in builders
sub _createBuilders
  {

    my ($self, %params) = @_;

    # Don't do anything if there aren't enough ifaces
    return unless ($self->enoughInterfaces());

    my $regenConfig = $params{regenConfig};

    my $global = EBox::Global->getInstance();
    my $network = $self->{'network'};

    my @ifaces = @{$self->_realIfaces()};

    foreach my $iface (@ifaces) {
      $self->{builders}->{$iface} = {};
      if ( $self->_areRulesActive($iface, not $regenConfig) ) {
	# If there's any rule, for now use an HTBTreeBuilder
	$self->_createTree($iface, "HTB", $regenConfig);
	# Build every rule and stores the identifier in gconf to destroy
	# them afterwards
	$self->_buildGConfRules($iface, $regenConfig);
      }
      else {
	# For now, if no user_rules are given, use DefaultTreeBuilder
	$self->_createTree($iface, "default");
      }
    }

  }

# Build a new rule to the tree
# If not rules has been set or they're not enabled no added is made
sub _buildRule # ($iface, $rule_ref, $test)
  {

    my ( $self, $iface, $rule_ref, $test ) = @_;

    if ( $self->{builders}->{$iface}->isa('EBox::TrafficShaping::TreeBuilder::Default') ) {
      # Build a new HTB
      $self->_createTree($iface, "HTB");
    }

    # Actually build the rule in the builder or just test if it's possible
    $self->_buildANewRule($iface, $rule_ref, $test);

  }

# Finally, adds from GConf rules to tree builder
# Throws Internal exception if not normal builder
# is asked to build the rule
sub _buildANewRule # ($iface, $rule_ref, $test?)
{

    my ($self, $iface, $rule_ref, $test) = @_;

    my $htbBuilder = $self->{builders}->{$iface};

    if ( $htbBuilder->isa('EBox::TrafficShaping::TreeBuilder::HTB')) {
        my $src = undef;
        my $srcObj = undef;
        my $objs = $self->{'objects'};
        if ( ( defined ( $rule_ref->{source} )
               and $rule_ref->{source} ne '' ) and
             ( $rule_ref->{source}->isa('EBox::Types::IPAddr') or
               $rule_ref->{source}->isa('EBox::Types::MACAddr'))
           ) {
            $src = $rule_ref->{source};
            $srcObj = undef;
        } elsif ( ( not defined ( $rule_ref->{source} ))
                  or $rule_ref->{source}->isa('EBox::Types::Union::Text')) {
            $src = undef;
            $srcObj = undef;
        } else {
            # If an object is provided no source is needed to set a rule but
            # then attaching filters according to members of this object
            $src = undef;
            $srcObj =  $rule_ref->{source};
            return unless (@{$objs->objectAddresses($srcObj)});
        }

        # The same related to destination
        my $dst = undef;
        my $dstObj = undef;
        if ( ( defined ( $rule_ref->{destination} ) and
               $rule_ref->{destination} ne '' ) and
             ( $rule_ref->{destination}->isa('EBox::Types::IPAddr'))) {
            $dst = $rule_ref->{destination};
            $dstObj = undef;
        } elsif ( not defined ( $rule_ref->{destination} )
                  or ($rule_ref->{destination}->isa('EBox::Types::Union::Text'))) {
            $dst = undef;
            $dstObj = undef;
        } else {
            # If an object is provided no source is needed to set a rule but
            # then attaching filters according to members of this object
            $dst = undef;
            $dstObj =  $rule_ref->{destination} ;
            return unless (@{$objs->objectAddresses($dstObj)});
        }

        # Set a filter with objects if src or dst are not objects
        my $service = undef;
        $service = $rule_ref->{service}; # unless ( $srcObj or $dstObj );

        # Only to dump enabled rules, however testing adding new rules
        # is done, no matter if the rule is enabled or not
        if ( $rule_ref->{enabled} or $test ) {
            $htbBuilder->buildRule(
                                   service        => $service,
                                   source         => $src,
                                   destination    => $dst,
                                   guaranteedRate => $rule_ref->{guaranteedRate},
                                   limitedRate    => $rule_ref->{limitedRate},
                                   priority       => $rule_ref->{priority},
                                   identifier     => $rule_ref->{identifier},
                                   testing        => $test,
                                  );
        }
        # If an object is provided, attach filters to every member to the
        # flow object id
        # Only if not testing
        if ( not $test ) {
            if ( $srcObj and not $dstObj) {
                $self->_buildObjMembers( treeBuilder  => $htbBuilder,
                                         what         => 'source',
                                         objectName   => $rule_ref->{source},
                                         ruleRelated  => $rule_ref->{identifier},
                                         serviceAssoc => $rule_ref->{service},
                                         where        => $rule_ref->{destination},
                                         rulePriority => $rule_ref->{priority},
                                       );
            } elsif ( $dstObj and not $srcObj ) {
                $self->_buildObjMembers(
                                        treeBuilder  => $htbBuilder,
                                        what         => 'destination',
                                        objectName   => $rule_ref->{destination},
                                        ruleRelated  => $rule_ref->{identifier},
                                        serviceAssoc => $rule_ref->{service},
                                        where        => $rule_ref->{source},
                                        rulePriority => $rule_ref->{priority},
                                       );
            } elsif ( $dstObj and $srcObj ) {
                # We have to build whole station
                $self->_buildObjToObj( treeBuilder  => $htbBuilder,
                                       srcObject    => $rule_ref->{source},
                                       dstObject    => $rule_ref->{destination},
                                       ruleRelated  => $rule_ref->{identifier},
                                       serviceAssoc => $rule_ref->{service},
                                       rulePriority => $rule_ref->{priority},
                                     );
            }
        }

    } else {
        throw EBox::Exceptions::Internal('Tree builder which is not HTB ' .
                                         'which actually builds the rules');
    }

}

# Build a necessary classify rule to each member from an object into a
# HTB tree
# It receives four parameters:
#  - treeBuilder - the HTB tree builder
#  - what - what is the object (source, destination)
#  - objectName - the object's name
#  - ruleRelated - the rule identifier assigned to the object
#  - serviceAssoc - the service associated if any
#  - where - the counterpart (<EBox::Types::IPAddr> or <EBox::Types::MACAddr>)
#  - rulePriority - the rule priority
sub _buildObjMembers
  {

    my ($self, %args ) = @_;
    my $treeBuilder = $args{treeBuilder};
    my $what = $args{what};
    my $objectName = $args{objectName};
    my $ruleRelated = $args{ruleRelated};
    my $serviceAssoc = $args{serviceAssoc};
    my $where = $args{where};
    my $rulePriority = $args{rulePriority};

    unless ( $objectName ) {
      return;
    }

    # Get the object's members
    my $global = EBox::Global->getInstance();
    my $objs = $self->{'objects'};

    my $membs_ref = $objs->objectMembers($objectName);

    # Set a different filter identifier for each object's member
    my $filterId = $ruleRelated;
    foreach my $member_ref (@{$membs_ref}) {
      my $ip = new EBox::Types::IPAddr(
				       ip => $member_ref->{ip},
				       mask => $member_ref->{mask},
				       fieldName => 'ip'
				      );
      my $srcAddr;
      my $dstAddr;
      if ( $what eq 'source' ) {
	$srcAddr = $ip;
	$dstAddr = $where;
      }
      elsif ( $what eq 'destination') {
	$srcAddr = $where;
	$dstAddr = $ip;
      }
      $treeBuilder->addFilter(
			      leafClassId => $ruleRelated,
			      priority    => $rulePriority,
			      srcAddr     => $srcAddr,
			      dstAddr     => $dstAddr,
			      service     => $serviceAssoc,
			      id          => $filterId,
			     );
      $filterId++;
      # If there's a MAC address and what != source not to add since
      # it has no sense
      # TODO: Objects can be only set with an IP.
#      if ( $member_ref->{mac} and ( $what eq 'source' )) {
#	my $mac = new EBox::Types::MACAddr(
#					   value => $member_ref->{mac},
#					  );
#	$filterValue->{srcAddr} = $mac;
#	$filterValue->{dstAddr} = $where;
#	$treeBuilder->addFilter( leafClassId => $ruleRelated,
#				 filterValue => $filterValue);
#	$filterId++;
#      }
      # Just adding one could be a solution to have different filter identifiers
    }

  }

# Build a n x m rules among each member of the both object with each other
# It receives four parameters:
#  - treeBuilder - the HTB tree builder
#  - srcObject - source object's name
#  - dstObject - destination object's name
#  - ruleRelated - the rule identifier assigned to the filters to add
#  - serviceAssoc - the service associated if any
#  - rulePriority - the rule priority
sub _buildObjToObj
  {

    my ($self, %args) = @_;

    my $global = EBox::Global->getInstance();
    my $objs = $self->{'objects'};

    my $srcMembs_ref = $objs->objectMembers($args{srcObject});
    my $dstMembs_ref = $objs->objectMembers($args{dstObject});

    my $filterId = $args{ruleRelated};

    foreach my $srcMember_ref (@{$srcMembs_ref}) {
      my $srcAddr = new EBox::Types::IPAddr(
					    ip   => $srcMember_ref->{ip},
					    mask => $srcMember_ref->{mask},
					   );
      foreach my $dstMember_ref (@{$dstMembs_ref}) {
	my $dstAddr = new EBox::Types::IPAddr(
					      ip   => $dstMember_ref->{ip},
					      mask => $dstMember_ref->{mask},
					     );
	$args{treeBuilder}->addFilter(
				      leafClassId => $args{ruleRelated},
				      priority    => $args{rulePriority},
				      srcAddr     => $srcAddr,
				      dstAddr     => $dstAddr,
				      service     => $args{serviceAssoc},
				      id          => $filterId,
				     );
	$filterId++;
      }
    }

  }


# Update a rule from the builder taking arguments from GConf
sub _updateRule # (iface, ruleId, ruleParams_ref?, test?)
  {

    my ($self, $iface, $ruleId, $ruleParams_ref, $test) = @_;

    my $minorNumber = $self->_mapRuleToClassId($ruleId);
    # Update the rule stating the same leaf class id (If test not do)
    $self->{builders}->{$iface}->updateRule(
					    identifier     => $minorNumber,
					    service        => $ruleParams_ref->{service},
					    source         => $ruleParams_ref->{source},
					    destination    => $ruleParams_ref->{destination},
					    guaranteedRate => $ruleParams_ref->{guaranteedRate},
					    limitedRate    => $ruleParams_ref->{limitedRate},
					    priority       => $ruleParams_ref->{priority},
					    testing        => $test,
					   );

  }


###
# Naming convention helper functions
###

# Set the identifiers to the correct intervals with this function
# (Ticket #481)
# Returns a Int among MIN_ID_VALUE and MAX_ID_VALUE
sub _nextMap # (ruleId?, test?)
  {

    my ($self, $ruleId, $test) = @_;

    if ( not defined ( $self->{nextIdentifier} ) ) {
      $self->{nextIdentifier} = MIN_ID_VALUE;
      $self->{classIdMap} = {};
    }

    my $retValue = $self->{nextIdentifier};

    if ( defined ( $ruleId ) and not $test ) {
      # We store at a hash the ruleId vs. class id
      $self->{classIdMap}->{$ruleId} = $retValue;
    }

    if ( $self->{nextIdentifier} < MAX_ID_VALUE and
        (not $test)) {
      # Sums min id value -> 0x100
      $self->{nextIdentifier} += MIN_ID_VALUE;
    }

    return $retValue;

  }

# Returns the class id mapped at a rule identifier
# Undef if no map has been created
sub _mapRuleToClassId # (ruleId)
  {

    my ($self, $ruleId) = @_;

    if ( defined ( $self->{classIdMap} )) {
      return $self->{classIdMap}->{$ruleId};
    }
    else {
      return undef;
    }

  }

###
# Network observer helper functions
###

# Remove remainder models if there are no enough interfaces
sub _removeIfNotEnoughRemainderModels
{

    my ($self, $iface) = @_;

    my $nExt = @{$self->{network}->ExternalIfaces()};
    my $nInt = @{$self->{network}->InternalIfaces()};

    if ( $self->{network}->ifaceIsExternal($iface) ) {
        $nExt--;
        $nInt++;
    } else {
        $nInt--;
        $nExt++;
    }
    if ( $nExt == 0 or $nInt == 0 ) {
        my $manager = EBox::Model::ModelManager->instance();
        foreach my $ifaceWithModel ( keys %{$self->{ruleModels}} ) {
            my $model = $self->{ruleModels}->{$ifaceWithModel};
            if ( defined ( $model )) {
                $model->removeAll(1);
                $manager->removeModel($model->contextName());
            }
        }
    }

}


###
# Log Admin related functions
###

# Admin log related to update rule
# References to the old dir and new dir are passed
sub _logUpdate # (new_ref)
  {
    my ($self, $new_ref) = @_;

    # Strings to print to log
    my $newValues = q{};

    $newValues .= " " . __("Protocol") . " " . $new_ref->{protocol};
    $newValues .= " " . __("Port") . " " . $new_ref->{port};
    $newValues .= " " . __("Guaranteed Rate") . " " . $new_ref->{guaranteedRate};
    $newValues .= " " . __("Limited Rate") . " " . $new_ref->{limitedRate};
    $newValues .= " " . __("Priority") . " " . $new_ref->{priority};

#    logAdminDeferred("trafficshaping", "updateRule",
#		     "values=$newValues");

  }

# Set the actions to log
sub _setLogAdminActions
  {

    my ($self) = @_;

    $self->{actions} = {};
#    $self->{actions}->{addRule} = __n("Added rule under interface: {iface} with protocol: " .
#				      "{protocol} port: {port} guaranteed " .
#				      "rate: {gRate} limited rate to: {lRate} ".
#				      "priority: {priority} enabled: {enabled}");
#    $self->{actions}->{removeRule} = __n("Removed rule under interface: {iface} with protocol: " .
#					 "{protocol} port: {port} guaranteed " .
#					 "rate: {gRate} limited rate to: {lRate} ".
#					 "priority: {priority} enabled: {enabled}");
#    $self->{actions}->{enableRule} = __n("Enabled rule under interface: {iface} with protocol: " .
#					 "{protocol} port: {port} guaranteed " .
#					 "rate: {gRate} limited rate to: {lRate} ".
#					 "priority: {priority}");
#    $self->{actions}->{disableRule} = __n("Disabled rule under interface: {iface} with protocol: " .
#					 "{protocol} port: {port} guaranteed " .
#					 "rate: {gRate} limited rate to: {lRate} ".
#					 "priority: {priority}");
#
#    $self->{actions}->{updateRule} = __n("Update rule under interface: {iface} for the following " .
#					 "values:{values}");

  }

###################################
# Iptables related functions
###################################

# Delete TrafficShaping filter chain in Iptables Linux kernel struct
sub _deleteChains # (iface)
{

    my ( $self, $iface ) = @_;

    try {
        $self->_pf( "-t mangle -F EBOX-SHAPER-$iface" );
        $self->_pf( "-t mangle -X EBOX-SHAPER-$iface" );
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 2 or
                $exception->exitValue() == 1) {
            # The chain does not exist, ignore
            ;
        } else {
            $exception->throw();
        }
    };

}

sub _deletePostroutingChain # (iface)
{

    my ($self) = @_;

    my $chain = "EBOX-SHAPER";
    try {
        $self->_pf("-t mangle -D POSTROUTING -j EBOX-SHAPER");
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            # Ignoring
            ;
        }
    };

    try {
        $self->_pf("-t mangle -F EBOX-SHAPER");
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            # Ignoring
            ;
        }
    };

    try {
        $self->_pf("-t mangle -X EBOX-SHAPER");
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            # Ignoring
            ;
        }
    };
}

sub _createPostroutingChain # (iface)
{

    my ($self) = @_;

    my $chain = "EBOX-SHAPER";
    try {
        $self->_pf("-t mangle -N  EBOX-SHAPER");
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            # Ignoring
            ;
        }
    };

    try {
        $self->_pf("-t mangle -I POSTROUTING -j EBOX-SHAPER");
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            # Ignoring
            ;
        }
    };
}



sub _resetChain # (iface)
{

    my ($self, $iface) = @_;

    # Delete any previous chain
    $self->_deleteChains($iface);

    my $chain = "EBOX-SHAPER-$iface";
    try {
        $self->_pf("-t mangle -N $chain");
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            EBox::info("$chain already exists");
        }
    };

    my $rule = "-t mangle -I EBOX-SHAPER -o $iface -j $chain";
    try {
        $self->_pf($rule);
    } catch EBox::Exceptions::Sudo::Command with {
        my $exception = shift;
        if ($exception->exitValue() == 1) {
            EBox::info($rule);
        }
    };
  }

# Execute an array of iptables commands
sub _executeIptablesCmds # (iptablesCmds_ref)
  {

    my ($self, $iptablesCmds_ref) = @_;

    foreach my $ipTablesCmd (@{$iptablesCmds_ref}) {
      #EBox::info("iptables $ipTablesCmd");
      $self->_pf($ipTablesCmd);
    }

  }


 # Run a iptables command
 sub _pf
   {
      my ($self, $cmd) = @_;
      EBox::Sudo::root("/sbin/iptables $cmd");
   }

# Fetch configured interfaces in this module
sub _configuredInterfaces
{
    my ($self) = @_;

    my @ifaces;
    for my $iface (@{ $self->all_dirs_base('')}) {
        push (@ifaces, $iface) if ($iface ne 'InterfaceRate');
    }
    return \@ifaces;
}

# For all those ppp ifaces fetch its  ethernet iface
sub _realIfaces
{
    my ($self) = @_;
    my $network = $self->{'network'};
    return [map {$network->realIface($_)} @{$network->ifaces()}];
}

# Method: l7FilterEnabled
#
#   return wether l7 (application layer) filtering is available or not. This
#   will require an appropatie kernel, iptables and the module l7-protocols
#
#   Returns:
#      boolean - whether l7 fitler is available or not
sub l7FilterEnabled
{
    return 0 unless (EBox::Global->getInstance()->modExists('l7-protocols'));
    my $out = `modinfo xt_layer7 2>&1`;
    return ( $? == 0 );
}

# Method: modelsBackupFiles
#
#   Override <EBox::Model::ModelProvider::modelsBackupFiles>
#   to avoid nasty issues with InterfaceRate and recursive loops
sub modelsBackupFiles
{

}

# Method: modelsRestoreFiles
#
#   Override <EBox::Model::ModelProvider::modelsRestoreFiles>
#   to avoid nasty issues with InterfaceRate and recursive loops
sub modelsRestoreFiles
{

}

1;

