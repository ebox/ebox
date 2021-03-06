# Copyright (C) 2005  Warp Networks S.L., DBS Servicios Informaticos S.L.
# Copyright (C) 2007  Warp Networks S.L.
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

package EBox::DHCP;

use strict;
use warnings;

use base qw(EBox::Module::Service
		EBox::NetworkObserver
		EBox::LogObserver
		EBox::Model::ModelProvider
		EBox::Model::CompositeProvider);

use EBox::Config;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataNotFound;
use EBox::Gettext;
use EBox::Global;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::Objects;
use EBox::Validate qw(:all);

use EBox::Model::ModelManager;
use EBox::Model::CompositeManager;

use EBox::Sudo qw(:all);
use EBox::NetWrappers qw(:all);
use EBox::Service;
use EBox::DHCPLogHelper;

use EBox::Dashboard::Section;
use EBox::Dashboard::List;


# Models & Composites
use EBox::Common::Model::EnableForm;
use EBox::DHCP::Composite::AdvancedOptions;
use EBox::DHCP::Composite::InterfaceConfiguration;
use EBox::DHCP::Composite::General;
use EBox::DHCP::Composite::Interfaces;
use EBox::DHCP::Composite::OptionsTab;
use EBox::DHCP::Model::DynamicDNS;
use EBox::DHCP::Model::FixedAddressTable;
use EBox::DHCP::Model::LeaseTimes;
use EBox::DHCP::Model::Options;
use EBox::DHCP::Model::RangeInfo;
use EBox::DHCP::Model::RangeTable;
use EBox::DHCP::Model::ThinClientOptions;
use Net::IP;
use HTML::Mason;
use Error qw(:try);
use Perl6::Junction qw(any);
use Text::DHCPLeases;

# Module local conf stuff
use constant DHCPCONFFILE => "/etc/dhcp3/dhcpd.conf";
use constant LEASEFILE => "/var/lib/dhcp3/dhcpd.leases";
use constant PIDFILE => "/var/run/dhcpd.pid";
use constant DHCP_SERVICE => "ebox.dhcpd3";
use constant TFTP_SERVICE => "tftpd-hpa";

use constant CONF_DIR => EBox::Config::conf() . 'dhcp/';
use constant PLUGIN_CONF_SUBDIR => 'plugins/';
use constant TFTPD_CONF_DIR => '/var/lib/tftpboot/';

# Group: Public and protected methods

# Constructor: _create
#
#    Create the ebox-dhcp module
#
# Overrides:
#
#    <EBox::Module::Service::_create>
#
sub _create
{
	my $class = shift;
	my $self  = $class->SUPER::_create(name => 'dhcp',
                                           printableName => 'DHCP',
                                           domain => 'ebox-dhcp',
                                           @_);
	bless ($self, $class);

	return $self;
}

sub domain
{
	return 'ebox-dhcp';
}

# Method: usedFiles
#
#	Override EBox::Module::Service::usedFiles
#
sub usedFiles
{
	return [
		{
		 'file' => DHCPCONFFILE,
		 'module' => 'dhcp',
                 'reason' => __x('{server} configuration file', server => 'dhcpd'),
		}
	       ];
}

# Method: enableActions
#
# 	Override EBox::Module::Service::enableActions
#
sub enableActions
{
    root(EBox::Config::share() . '/ebox-dhcp/ebox-dhcp-enable');
}

# Method: _daemons
#
#	Override EBox::Module::Service::daemons
#
sub _daemons
{
    return [ { 'name' => DHCP_SERVICE } ];
}

# Method: _setConf
#
#      Writes the configuration files
#
# Overrides:
#
#      <EBox::Module::Base::_setConf>
#
sub _setConf
{
    my ($self) = @_;
    $self->_setDHCPConf();
    $self->_setTFTPDConf();
}

# Method: menu
#
# Overrides:
#
#     <EBox::Module::menu>
#
#
sub menu
{
        my ($self, $root) = @_;
        $root->add(new EBox::Menu::Item('url' => 'DHCP/Composite/General',
                                        'text' => $self->printableName(),
                                        'separator' => 'Infrastructure',
                                        'order' => 410));
}

# Method: depends
#
#     DHCP depends on DNS configuration only if the Dynamic DNS
#     feature is done.
#
# Overrides:
#
#     <EBox::Module::Base::depends>
#
sub depends
{
    my ($self) = @_;

    my $dependsList = $self->SUPER::depends();
    if ( $self->_dynamicDNSEnabled() ) {
        push(@{$dependsList}, 'dns');
    }

    return $dependsList;

}

# Method: models
#
# Overrides:
#
#     <EBox::Model::ModelProvider::models>
#
sub models
{

    my ($self) = @_;

    my @models;
   my $net = EBox::Global->modInstance('network');
    foreach my $iface (@{$net->allIfaces()}) {
        if ( $net->ifaceMethod($iface) eq 'static' ) {
            # Create models
            $self->{rangeModel}->{$iface} =
              new EBox::DHCP::Model::RangeTable(
                                                gconfmodule => $self,
                                                directory   => "RangeTable/$iface",
                                                interface   => $iface
                                               );
            push ( @models, $self->{rangeModel}->{$iface} );
            $self->{fixedAddrModel}->{$iface} =
              new EBox::DHCP::Model::FixedAddressTable(
                                                       gconfmodule => $self,
                                                       directory   => "FixedAddressTable/$iface",
                                                       interface   => $iface);
            push ( @models, $self->{fixedAddrModel}->{$iface} );
            $self->{optionsModel}->{$iface} =
              new EBox::DHCP::Model::Options(
                                             gconfmodule => $self,
                                             directory   => "Options/$iface",
                                             interface   => $iface);
            push ( @models, $self->{optionsModel}->{$iface} );
            $self->{leaseTimesModel}->{$iface} =
              new EBox::DHCP::Model::LeaseTimes(
                                                gconfmodule => $self,
                                                directory   => "LeaseTimes/$iface",
                                                interface   => $iface);
            push ( @models, $self->{leaseTimesModel}->{$iface} );
            $self->{thinClientModel}->{$iface} =
              new EBox::DHCP::Model::ThinClientOptions(
                                                       gconfmodule => $self,
                                                       directory   => "ThinClientOptions/$iface",
                                                       interface   => $iface);
            push ( @models, $self->{thinClientModel}->{$iface} );
            $self->{dynamicDNSModel}->{$iface} =
              new EBox::DHCP::Model::DynamicDNS(
                                                gconfmodule => $self,
                                                directory   => "DynamicDNS/$iface",
                                                interface   => $iface);
            push ( @models, $self->{dynamicDNSModel}->{$iface} );
            $self->{rangeInfoModel}->{$iface} =
              new EBox::DHCP::Model::RangeInfo(
                                               gconfmodule => $self,
                                               directory   => "RangeInfo/$iface",
                                               interface   => $iface);
            push ( @models, $self->{rangeInfoModel}->{$iface});
        }
    }

    return \@models;

}

# Method: _exposedMethods
#
# Overrides:
#
#     <EBox::Model::ModelProvider::_exposedMethods>
#
sub _exposedMethods
{
    my ($self) = @_;

    my %methods =
      ( 'setOption' => { action   => 'set',
                         path     => [ 'Options' ],
                         indexes  => [ 'id' ],
                       },
        'setDefaultGateway' => { action   => 'set',
                                 path     => [ 'Options' ],
                                 indexes  => [ 'id' ],
                                 selector => [ 'default_gateway' ],
                               },
        'addRange'          => { action   => 'add',
                                 path     => [ 'RangeTable' ],
                               },
        'removeRange'       => { action   => 'del',
                                 path     => [ 'RangeTable' ],
                                 indexes  => [ 'name' ],
                               },
        'setRange'          => { action   => 'set',
                                 path     => [ 'RangeTable' ],
                                 indexes  => [ 'name' ],
                               },
        'addFixedAddress'   => { action   => 'add',
                                 path     => [ 'FixedAddressTable' ],
                               },
        'setFixedAddress'   => { action   => 'set',
                                 path     => [ 'FixedAddressTable' ],
                                 indexes  => [ 'name' ],
                               },
        'removeFixedAddress' => { action   => 'del',
                                  path     => [ 'FixedAddressTable' ],
                                  indexes  => [ 'name' ],
                                },
        'setLeases' => { action  => 'set',
                         path    => [ 'LeaseTimes' ],
                         indexes => [ 'id' ],
                       },
        );
    return \%methods;

}

# Method: composites
#
# Overrides:
#
#     <EBox::Model::CompositeProvider::composites>
#
sub composites
{

    my ($self) = @_;

    my @composites;
    my $net = EBox::Global->modInstance('network');
    foreach my $iface (@{$net->allIfaces()}) {
        if ( $net->ifaceMethod($iface) eq 'static' ) {
            # Create models
            push ( @composites,
                   new EBox::DHCP::Composite::InterfaceConfiguration(interface => $iface));
            push ( @composites,
                   new EBox::DHCP::Composite::OptionsTab(interface => $iface));
            push ( @composites,
                   new EBox::DHCP::Composite::AdvancedOptions(interface => $iface));
        }
    }
    push ( @composites,
           new EBox::DHCP::Composite::Interfaces());
    push ( @composites,
           new EBox::DHCP::Composite::General());

    return \@composites;

}

# Method: initRange
#
#	Return the initial host address range for a given interface
#
# Parameters:
#
#	iface - String interface name
#
# Returns:
#
#	String - containing the initial range
#
sub initRange # (interface)
{
	my ($self, $iface) = @_;

	my $net = EBox::Global->modInstance('network');
	my $address = $net->ifaceAddress($iface);
	my $netmask = $net->ifaceNetmask($iface);

	my $network = ip_network($address, $netmask);
	my ($first, $last) = $network =~ /(.*)\.(\d+)$/;
	my $init_range = $first . "." . ($last+1);
	return $init_range;
}

# Method: endRange
#
#	Return the final host address range for a given interface
#
# Parameters:
#
#	iface - String interface name
#
# Returns:
#
#	string - containing the final range
#
sub endRange # (interface)
{
	my ($self, $iface) = @_;

	my $net = EBox::Global->modInstance('network');
	my $address = $net->ifaceAddress($iface);
	my $netmask = $net->ifaceNetmask($iface);

	my $broadcast = ip_broadcast($address, $netmask);
	my ($first, $last) = $broadcast =~ /(.*)\.(\d+)$/;
	my $end_range = $first . "." . ($last-1);
	return $end_range;
}

# Method: defaultGateway
#
#	Get the default gateway that will be sent to DHCP clients for a
#	given interface
#
# Parameters:
#
#   	iface - interface name
#
# Returns:
#
#   	string - the default gateway in a IP address form
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
sub defaultGateway # (iface)
{
	my ($self, $iface) = @_;

	my $network = EBox::Global->modInstance('network');

	#if iface doesn't exists throw exception
	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
				value => $iface);
	}

	#if iface is not static, throw exception
	if($network->ifaceMethod($iface) ne 'static') {
		throw EBox::Exceptions::External(__x("{iface} is not static",
			iface => $iface));
	}

        return $self->_getModel('optionsModel', $iface)->defaultGateway();
}

# Method: searchDomain
#
#	Get the search domain that will be sent to DHCP clients for a
#	given interface
#
# Parameters:
#
#   	iface - String interface name
#
# Returns:
#
# 	String - the search domain
#
#       undef  - if the none search domain has been set
#
sub searchDomain # (iface)
{
	my ($self, $iface) = @_;

	my $network = EBox::Global->modInstance('network');

	#if iface doesn't exists throw exception
	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
				value => $iface);
	}

	#if iface is not static, throw exception
	if($network->ifaceMethod($iface) ne 'static') {
		throw EBox::Exceptions::External(__x("{iface} is not static",
			iface => $iface));
	}

#	$self->get_string("$iface/search");
        return $self->_getModel('optionsModel', $iface)->searchDomain();
}

# Method: nameserver
#
#	Get the nameserver that will be sent to DHCP clients for a
#	given interface
#
# Parameters:
#
#   	iface - String interface name
#   	number - Int nameserver number (1 or 2)
#
#   Returns:
#
#   	string - the nameserver or undef if there is no
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
sub nameserver # (iface,number)
{
	my ($self, $iface, $number) = @_;

        if ( not defined ( $number )) {
            throw EBox::Exceptions::MissingArgument('number');
        }
	my $network = EBox::Global->modInstance('network');

	#if iface doesn't exists throw exception
	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
				value => $iface);
	}

	#if iface is not static, throw exception
	if($network->ifaceMethod($iface) ne 'static') {
		throw EBox::Exceptions::External(__x("{iface} is not static",
			iface => $iface));
	}

#	$self->get_string("$iface/nameserver$number");
        return $self->_getModel('optionsModel', $iface)->nameserver($number);
}

# Method: ntpServer
#
#       Get the NTP server that will be sent to DHCP clients for a
#       given interface
#
# Parameters:
#
#       iface - String the interface name
#
# Returns:
#
#       String - the IP address for the NTP server, undef if no
#                NTP server has been configured
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
sub ntpServer # (iface)
{
    my ($self, $iface) = @_;

    my $network = EBox::Global->modInstance('network');
    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                                             value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
                                             iface => $iface));
    }

    return $self->_getModel('optionsModel', $iface)->ntpServer();

}

# Method: winsServer
#
#       Get the WINS server that will be sent to DHCP clients for a
#       given interface
#
# Parameters:
#
#       iface - String the interface name
#
# Returns:
#
#       String - the IP address for the WINS server, undef if no
#                WINS server has been configured
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the interface is not
#       static or the given type is none of the suggested ones
#
#       <EBox::Exceptions::DataNotFound> - thrown if the interface is
#       not found
#
#       <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#       argument is missing
#
sub winsServer # (iface)
{
    my ($self, $iface) = @_;

    my $network = EBox::Global->modInstance('network');
    #if iface doesn't exists throw exception
    if (not $iface or not $network->ifaceExists($iface)) {
        throw EBox::Exceptions::DataNotFound(data => __('Interface'),
                                             value => $iface);
    }

    #if iface is not static, throw exception
    if($network->ifaceMethod($iface) ne 'static') {
        throw EBox::Exceptions::External(__x("{iface} is not static",
                                             iface => $iface));
    }

    return $self->_getModel('optionsModel', $iface)->winsServer();

}

# Method: staticRoutes
#
#	Get the static routes. It polls the eBox modules which
#	implements <EBox::DHCP::StaticRouteProvider>
#
# Returns:
#
#	hash ref - contating the static toutes in hash references. The
#	key is the subnet in CIDR notation that denotes where is
#	appliable the new route.  The values are hash reference with
#	the keys 'destination', 'netmask' and 'gw'
#
sub staticRoutes
{
  my ($self) = @_;
  my %staticRoutes = ();

  my @modules = @{ EBox::Global->modInstancesOfType('EBox::DHCP::StaticRouteProvider') };
  foreach  my $mod (@modules) {
    my @modStaticRoutes = @{ $mod->staticRoutes() };
    while (@modStaticRoutes) {
      my $net   = shift @modStaticRoutes;
      my $route = shift @modStaticRoutes;
      if (exists $staticRoutes{$net}) {
	push  @{$staticRoutes{$net}}, $route;
      }
      else {
	$staticRoutes{$net} = [$route];
      }
    }
  }

  return \%staticRoutes;
}

sub notifyStaticRoutesChange
{
  my ($self) = @_;
  $self->setAsChanged();
}


# Method: rangeAction
#
#	Set/add a range for a given interface
#
# Parameters:
#
#	iface - String Interface name
#       action - String to perform (add/set/del)
#
#       indexValue - String index to use to set a new value, it can be a
#       name, a from IP addr or a to IP addr.
#
#       indexField - String the field name to use as index
#
#	name - String the range name
#	from - String start of range, an ip address
#	to - String end of range, an ip address
#
#       - Named parameters
#
# Exceptions:
#
#    <EBox::Exceptions::DataNotFound> - Interface does not exist
#    <EBox::Exceptions::External> - interface is not static
#    <EBox::Exceptions::External - invalid range
#    <EBox::Exceptions::External - range overlap
#
sub rangeAction # (iface, name, from, to)
{
	my ($self, %args) = @_;

        my $iface = delete ($args{iface});
        my $action = delete ($args{action});
        unless ( $action eq any(qw(add set del))) {
            throw EBox::Exceptions::External(__('Not a valid action: add, set and del '
                                                . 'are available'));
        }

	my $network = EBox::Global->modInstance('network');

	#if iface doesn't exists throw exception
	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
				value => $iface);
	}

	#if iface is not static, throw exception
	if($network->ifaceMethod($iface) ne 'static') {
		throw EBox::Exceptions::External(__x("{iface} is not static",
			iface => $iface));
	}

        my $rangeModel = $self->_getModel('rangeModel', $iface);
        if ( $action eq 'add' ) {
            $rangeModel->add( name => $args{name},
                                                         from => $args{from},
                                                         to   => $args{to});
        } elsif ( $action eq 'set' ) {
            my $index = delete ( $args{indexValue} );
            my $indexField = delete ( $args{indexField} );
            my @args = map { $_ => $args{$_} } keys (%args);
            $rangeModel->setIndexField($indexField);
            $rangeModel->set( $index, @args );
        } elsif ( $action eq 'del' ) {
            my $index = delete ( $args{indexValue} );
            my $indexField = delete ( $args{indexField} );
            $rangeModel->setIndexField($indexField);
            $rangeModel->del( $index );
        }
}

# Method: ranges
#
#	Return all the set ranges for a given interface
#
# Parameters:
#
#	iface - String interface name
#
# Returns:
#
#	array ref - contating the ranges in hash references. Each hash holds
#	the keys 'name', 'from' and 'to'
#
# Exceptions:
#
#       <EBox::Exceptions::DataNotFound> - Interface does not exist
#
sub ranges # (iface)
{
	my ($self, $iface) = @_;

	my $global = EBox::Global->getInstance();
	my $network = EBox::Global->modInstance('network');

	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound('data' => __('Interface'),
						'value' => $iface);
	}

    my $model = $self->_getModel('rangeModel', $iface);
    my @ranges;
    for my $id (@{$model->ids()}) {
        my $row = $model->row($id);
        push (@ranges, {
                name => $row->valueByName('name'),
                from => $row->valueByName('from'),
                to => $row->valueByName('to')
                });
    }

    return \@ranges;
}

# Method: fixedAddressAction
#
#	Add/set/del a ip/mac pair as fixed address in a given interface.
#
# Parameters:
#
#	iface - String interface name
#       action - String the action to be performed (add/set/del)
#
#       indexValue - String the index element value, it may be the
#       name, the ip or the mac since they all are unique (Only
#       required for set/del actions)
#
#       indexField - String the field name to use as index (Only
#       required for set/del actions)
#
#	mac - String mac address
#	ip - String IPv4 address
#	name - String the mapping name
#
#   Exceptions:
#
#	DataNotFound - Interface does not exist
#	External - Interface is not configured as static
#	External - ip is not in the network for the given interface
#	External - ip overlap
#	External - ip already configured as fixed
#
sub fixedAddressAction
{
	my ($self, %args) = @_;

        my $iface = delete ( $args{iface} );
        my $action = delete ( $args{action} );
        unless ( any(qw(add set del)) eq $action ) {
            throw EBox::Exceptions::External(__('No valid action. Available '
                                                . 'ones are: add, set and del'));
        }

	my $network = EBox::Global->modInstance('network');

	#if iface doesn't exists throw exception
	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
				value => $iface);
	}

	#if iface is not static, throw exception
	if ($network->ifaceMethod($iface) ne 'static') {
		throw EBox::Exceptions::External(__x("{iface} is not static",
			iface => $iface));
	}

        my $model = $self->_getModel('fixedAddrModel', $iface);
        if ( $action eq 'add' ) {
            $model->add( name => $args{name},
                         mac  => $args{mac},
                         ip   => $args{ip});
        } elsif ( $action eq 'set' ) {
            my $index = delete ( $args{indexValue} );
            my $indexField = delete ( $args{indexField} );
            my @args = map { $_ => $args{$_} } keys (%args);
            $model->setIndexField($indexField);
            $model->set( $index, @args );
        } elsif ( $action eq 'del' ) {
            my $index = delete ( $args{indexValue} );
            my $indexField = delete ( $args{indexField} );
            $model->setIndexField($indexField);
            $model->del( $index );
        }


}

# Method: fixedAddresses
#
#	Return the list of fixed addreses
#
# Parameters:
#
#	iface - String interface name
#
# Returns:
#
#	array ref - contating the fixed addresses in hash refereces.
#	Each hash holds the keys 'mac', 'ip' and 'name'
#
# Exceptions:
#
#	<EBox::Exceptions::DataNotFound> - Interface does not exist
#
sub fixedAddresses # (interface)
{
	my ($self,$iface) = @_;

	my $network = EBox::Global->modInstance('network');

	#if iface doesn't exists throw exception
	if (not $iface or not $network->ifaceExists($iface)) {
		throw EBox::Exceptions::DataNotFound(data => __('Interface'),
				value => $iface);
	}

	#if iface is not static, throw exception
	if ($network->ifaceMethod($iface) ne 'static') {
		throw EBox::Exceptions::External(__x("{iface} is not static",
			iface => $iface));
	}

	my $model = $self->_getModel('fixedAddrModel', $iface);
	my @addrs;
	for my $id (@{$model->ids()}) {
		my $row = $model->row($id);
		push (@addrs, {
				name => $row->valueByName('name'),
				ip => $row->valueByName('ip'),
				mac => $row->valueByName('mac')
				});
	}

	return \@addrs;
}

# Group: Static or class methods

# Method: ConfDir
#
#      Get the DHCP configuration directory where to store the user
#      defined configuration files
#
# Parameters:
#
#      iface - String the interface which the user configuration file
#      is within
#
# Returns:
#
#      String - the configuration path
#
sub ConfDir
{
    my ($class, $iface) = @_;

    # Create directory unless it already exists
    unless ( -d CONF_DIR . $iface ) {
        mkdir ( CONF_DIR . $iface, 0755 );
    }
    my $pluginDir = CONF_DIR . $iface . '/' . PLUGIN_CONF_SUBDIR;
    unless ( -d $pluginDir ) {
        mkdir ( $pluginDir, 0755 );
    }
    return CONF_DIR . "$iface/";
}

# Method: TftpdRootDir
#
#      Get the default Tftpd root directory to store the firmwares
#      uploaded by our users
#
# Returns:
#
#      String - the tftpd root directory path
#
sub TftpdRootDir
{
    my ($class) = @_;

    # Create directory unless it already exists
    unless ( -d TFTPD_CONF_DIR ) {
        mkdir ( TFTPD_CONF_DIR, 0755 );
    }
    return TFTPD_CONF_DIR;
}

# Method: PluginConfDir
#
#      Get the DHCP plugin configuration directory where to store the user
#      defined configuration files
#
# Parameters:
#
#      iface - String the interface which the user configuration file
#      is within
#
# Returns:
#
#      String - the configuration path
#
sub PluginConfDir
{
    my ($class, $iface) = @_;

    my $pluginDir = CONF_DIR . $iface . '/' . PLUGIN_CONF_SUBDIR;
    unless ( -d $pluginDir ) {
        mkdir ( $pluginDir, 0755 );
    }
    return $pluginDir;
}


# Group: Network observer implementations

# Method: ifaceMethodChanged
#
# Implements:
#
#    <EBox::NetworkObserver::ifaceMethodChanged>
#
# Returns:
#
#     true - if the old method is 'static' and there are configured
#     ranges or fixed addresses attached to this interface
#     false - otherwise
#
sub ifaceMethodChanged # (iface, old_method, new_method)
{
    my ($self, $iface, $old_method, $new_method) = @_;

    # Mark managers as changed every time we attempt to change the
    # iface method from/to static
    if ($old_method eq 'static' or $new_method eq 'static') {
        my $manager = EBox::Model::ModelManager->instance();
        $manager->markAsChanged();
        $manager = EBox::Model::CompositeManager->Instance();
        $manager->markAsChanged();
    }

    if ($old_method eq 'static'
          and $new_method ne 'static') {
        my $rangeModel = $self->_getModel('rangeModel', $iface);
        if ( defined ( $rangeModel )) {
            return 1 if ( $rangeModel->size() > 0);
        }
        my $fixedAddrModel = $self->_getModel('fixedAddrModel', $iface);
        if ( defined ( $fixedAddrModel )) {
            return 1 if ( $fixedAddrModel->size() > 0);
        }
    }
    return 0;
}

# Method: vifaceAdded
#
#
# Implements:
#
#   <EBox::NetworkObserver::vifaceAdded>
#
# Exceptions:
#
#  <EBox::Exceptions::External> - thrown *if*:
#
#   - New Virtual interface IP overlaps any configured range
#   - New Virtual interface IP is a fixed IP address
#
sub vifaceAdded # (iface, viface, address, netmask)
{
	my ( $self, $iface, $viface, $address, $netmask) = @_;

	my $net = EBox::Global->modInstance('network');
	my $ip = new Net::IP($address);

        my $manager = EBox::Model::ModelManager->instance();

        my @rangeModels = @{$manager->model('/dhcp/RangeTable/*')};
        # Check that the new IP for the virtual interface isn't in any range
        foreach my $rangeModel (@rangeModels) {
            foreach my $id (@{$rangeModel->ids()}) {
                my $rangeRow = $rangeModel->row($id);
                my $from = $rangeRow->valueByName('from');
                my $to   = $rangeRow->valueByName('to');
                my $range = new Net::IP($from . ' - ' . $to);
                unless ( $ip->overlaps($range) == $IP_NO_OVERLAP ) {
                    throw EBox::Exceptions::External(
                    __x('The IP address of the virtual interface '
                            . 'you are trying to add is already used by the '
                            . "DHCP range '{range}' in the interface "
                            . "'{iface}'. Please, remove it before trying "
                            . 'to add a virtual interface using it.',
                            range => $rangeRow->valueByName('name'),
                            iface => $rangeModel->index()));
                }
            }
        }

        my @fixedAddrModels = @{$manager->model('/dhcp/FixedAddressTable/*')};
        # Check the new IP for the virtual interface is not a fixed address
        foreach my $fixedAddrModel (@fixedAddrModels) {
            foreach my $id (@{$fixedAddrModel->ids()}) {
                my $mappingRow = $fixedAddrModel->row($id);
                my $fixedIP = new Net::IP($mappingRow->valueByName('ip'));
                unless ( $ip->overlaps($fixedIP) == $IP_NO_OVERLAP ) {
                    throw EBox::Exceptions::External(
                           __x('The IP address of the virtual interface '
                               . 'you are trying to add is already used by the '
                               . "DHCP fixed address '{fixed}' in the "
                               . "interface '{iface}'. Please, remove it "
                               . 'before trying to add a virtual interface '
                               . 'using it.',
                               fixed => $mappingRow->valueByName('name'),
                               iface => $fixedAddrModel->index()));

                }
            }
        }
        # Mark managers as changed
        $manager->markAsChanged();
        my $compManager = EBox::Model::CompositeManager->Instance();
        $compManager->markAsChanged();

}

# Method:  vifaceDelete
#
# Implements:
#
#    <EBox::NetworkObserver::vifaceDelete>
#
# Returns:
#
#    true - if there are any configured range or fixed address for
#    this interface
#    false - otherwise
#
sub vifaceDelete # (iface, viface)
{
	my ( $self, $iface, $viface) = @_;
        my $manager = EBox::Model::ModelManager->instance();

        foreach my $modelName (qw(RangeTable FixedAddressTable Options)) {
            my $model = $manager->model("/dhcp/$modelName/$iface:$viface");
            my $nr = $model->size();
            if ( $nr > 0 ) {
                return 1;
            }
        }

        return 0;
}

# Method: staticIfaceAddressChanged
#
#       Return true *unless*:
#
#       - all ranges are still in the network
#       - new IP is not in any range
#       - all fixed addresses are still in the network
#       - new IP is not any fixed IP address
#
# Implements:
#
#       <EBox::NetworkObserver::staticIfaceAddressChanged>
#
sub staticIfaceAddressChanged # (iface, old_addr, old_mask, new_addr, new_mask)
{
	my ( $self, $iface, $old_addr, $old_mask, $new_addr, $new_mask) = @_;
#	my $nr = @{$self->ranges($iface)};
#	my $nf = @{$self->fixedAddresses($iface)};
#	if(($nr == 0) and ($nf == 0)){
#		return 0;
#	}

	my $ip = new Net::IP($new_addr);

	my $network = ip_network($new_addr, $new_mask);
	my $bits = bits_from_mask($new_mask);
	my $netIP = new Net::IP("$network/$bits");

        # Check ranges
        my $manager = EBox::Model::ModelManager->instance();
        my $rangeModel = $manager->model("/dhcp/RangeTable/$iface");
        foreach my $id (@{$rangeModel->ids()}) {
            my $rangeRow = $rangeModel->row($id);
            my $range = new Net::IP($rangeRow->valueByName('from')
                                    . ' - ' .
                                    $rangeRow->valueByName('to'));
            # Check the range is still in the network
            unless ($range->overlaps($netIP) == $IP_A_IN_B_OVERLAP){
                return 1;
            }
            # Check the new IP isn't in any range
            unless($ip->overlaps($range) == $IP_NO_OVERLAP ){
                return 1;
            }
        }
        my $fixedAddrModel = $manager->model("/dhcp/FixedAddressTable/$iface");
        foreach my $id (@{$fixedAddrModel->ids()}) {
            my $mappingRow = $fixedAddrModel->row($id);
            my $fixedIP = new Net::IP( $mappingRow->valueByName('ip') );
            # Check the fixed address is still in the network
            unless($fixedIP->overlaps($netIP) == $IP_A_IN_B_OVERLAP){
                return 1;
            }
            # Check the new IP isn't in any fixed address
            unless( $ip->overlaps($fixedIP) == $IP_NO_OVERLAP){
                return 1;
            }
        }

#	my $ranges = $self->ranges($iface);
#	foreach my $r (@{$ranges}){
#		my $r_ip = new Net::IP($r->{'from'} . " - " . $r->{'to'});
#		#check that the range is still in the network
#		unless($r_ip->overlaps($net_ip)==$IP_A_IN_B_OVERLAP){
#			return 1;
#		}
#		#check that the new IP isn't in any range
#		unless($ip->overlaps($r_ip)==$IP_NO_OVERLAP){
#			return 1;
#		}
#	}
#	my $fixedAddresses = $self->fixedAddresses($iface);
#	foreach my $f (@{$fixedAddresses}){
#		my $f_ip = new Net::IP($f->{'ip'});
#		#check that the fixed address is still in the network
#		unless($f_ip->overlaps($net_ip)==$IP_A_IN_B_OVERLAP){
#			return 1;
#		}
#		#check that the new IP isn't in any fixed address
#		unless($ip->overlaps($f_ip)==$IP_NO_OVERLAP){
#			return 1;
#		}
#	}

	return 0;
}

# Function: freeIface
#
#    Delete every single row from the models attached to this
#    interface
#
# Implements:
#
#    <EBox::NetworkObserver::freeIface>
#
#
sub freeIface #( self, iface )
{
	my ( $self, $iface ) = @_;
#	$self->delete_dir("$iface");
        $self->_removeDataModelsAttached($iface);

        my $manager = EBox::Model::ModelManager->instance();
        $manager->markAsChanged();
        $manager = EBox::Model::CompositeManager->Instance();
        $manager->markAsChanged();

	my $net = EBox::Global->modInstance('network');
	if ($net->ifaceMethod($iface) eq 'static') {
	  $self->_checkStaticIfaces(-1);
	}
}

# Method: freeViface
#
#    Delete every single row from the models attached to this virtual
#    interface
#
# Implements:
#
#    <EBox::NetworkObserver::freeViface>
#
#
sub freeViface #( self, iface, viface )
{
	my ( $self, $iface, $viface ) = @_;
#	$self->delete_dir("$iface:$viface");
        $self->_removeDataModelsAttached("$iface:$viface");

        my $manager = EBox::Model::ModelManager->instance();
        $manager->markAsChanged();
        $manager = EBox::Model::CompositeManager->Instance();
        $manager->markAsChanged();

#	my $net = EBox::Global->modInstance('network');
#	if ($net->ifaceMethod($viface) eq 'static') {
	  $self->_checkStaticIfaces(-1);
#	}

}

# Group: Private methods


# Impelment LogHelper interface
sub tableInfo {
	my $self = shift;

	my $titles = { 'timestamp' => __('Date'),
		'interface' => __('Interface'),
		'mac' => __('MAC address'),
		'ip' => __('IP'),
		'event' => __('Event')
	};
	my @order = ('timestamp', 'ip', 'mac', 'interface', 'event');
	my $events = {'leased' => __('Leased'), 'released' => __('Released') };

	return [{
		'name' => __('DHCP'),
		'index' => 'dhcp',
		'titles' => $titles,
		'order' => \@order,
		'tablename' => 'leases',
		'timecol' => 'timestamp',
		'filter' => ['interface', 'mac', 'ip'],
		'events' => $events,
		'eventcol' => 'event'
	}];
}

sub logHelper
{
	my $self = shift;

	return (new EBox::DHCPLogHelper);
}

sub _leaseIDFromIP
{
    my ($ip) = @_;
    my $id = 'a';
    #force every byte to use 3 digits to make sorting trivial
    my @bytes = split('\.', $ip);
    for my $byte (@bytes) {
        $id .= sprintf("%03d", $byte);
    }
    return $id;
}

sub _dhcpLeases
{
    my ($self) = @_;
    if(!defined($self->{'leases'})) {
        my $leases = Text::DHCPLeases->new(file => LEASEFILE);

        $self->{'leases'} = {};
        foreach my $lease ($leases->get_objects()) {
            my $id = _leaseIDFromIP($lease->ip_address());
            $self->{'leases'}->{$id} = $lease;
        }
    }
    return $self->{'leases'};
}

sub _leaseFromIP
{
    my ($self, $ip) = @_;

    my $leases = $self->_dhcpLeases();
    my $id = _leaseIDFromIP($ip);
    return $leases->{$id};
}

sub dhcpLeasesWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('dhcpleases');
    $widget->add($section);
    my $titles = [__('IP address'),__('MAC address'), __('Host name')];

    my $leases = $self->_dhcpLeases();

    my $ids = [];
    my $rows = {};
    foreach my $id (sort keys (%{$leases})) {
        my $lease = $leases->{$id};
        if($lease->binding_state() eq 'active') {
            my $hostname = $lease->client_hostname();
            $hostname =~ s/"//g;
            push(@{$ids}, $id);
            $rows->{$id} = [$lease->ip_address(),$lease->mac_address(),
                            $hostname];
        }
    }
    $section->add(new EBox::Dashboard::List(undef, $titles, $ids, $rows));
}

### Method: widgets
#
#   Overrides <EBox::Module::Base::widgets>
#
sub widgets
{
    return {
        'dhcpleases' => {
            'title' => __("DHCP leases"),
            'widget' => \&dhcpLeasesWidget,
            'default' => 1
        }
    };
}

# Group: Private methods

# Method: _setDHCPConf
#
#     Updates the dhcpd.conf file
#
sub _setDHCPConf
{
    my $self = shift;

    my $net = EBox::Global->modInstance('network');
    my $staticRoutes_r =  $self->staticRoutes();

    my $ifacesInfo = $self->_ifacesInfo($staticRoutes_r);
    my @params = ();
    push @params, ('dnsone' => $net->nameserverOne());
    push @params, ('dnstwo' => $net->nameserverTwo());
    push @params, ('thinClientOption' =>
                   $self->_areThereThinClientOptions($ifacesInfo));
    push @params, ('ifaces' => $ifacesInfo);
    push @params, ('real_ifaces' => $self->_realIfaces());
    my $dynamicDNSEnabled = $self->_dynamicDNSEnabled($ifacesInfo);
    if ( $dynamicDNSEnabled ) {
        push @params, ('dynamicDNSEnabled' => $dynamicDNSEnabled);
        push @params, ('keysFile' => $self->_keysFile());
    }

    $self->writeConfFile(DHCPCONFFILE, "dhcp/dhcpd.conf.mas", \@params);
}

# Method: _setTFTPDConf
#
#     Set the proper files on the TFTPD root dir
#
sub _setTFTPDConf
{
}

# Method: _ifacesInfo
#
#      Return a well structure to configure dhcp3-server using the
#      data installed in the module as well as the static routes
#      provided by <EBox::DHCP::StaticRouteProvider> modules
#
# Parameters:
#
#      staticRouters - hash ref containing those static routes to add
#      to a network which acts as key and the routes as value.
#
# Returns:
#
#      hash ref - an structure storing the required information for
#      dhcpd configuration
#
sub _ifacesInfo
{
  my ($self, $staticRoutes_r) = @_;

  my $net = EBox::Global->modInstance('network');
  my $ifaces = $net->allIfaces();

  my %iflist;
  foreach my $iface (@{$ifaces}) {
    if ($net->ifaceMethod($iface) eq 'static') {
      my $address = $net->ifaceAddress($iface);
      my $netmask = $net->ifaceNetmask($iface);
      my $network = ip_network($address, $netmask);

      $iflist{$iface}->{'net'} = $network;
      $iflist{$iface}->{'address'} = $address;
      $iflist{$iface}->{'netmask'} = $netmask;
      $iflist{$iface}->{'ranges'} = $self->ranges($iface);
      $iflist{$iface}->{'fixed'} = $self->fixedAddresses($iface);

      # look if we have static routes for this network
      my $netWithMask = EBox::NetWrappers::to_network_with_mask($network, $netmask);
       $iflist{$iface}->{'staticRoutes'} =  $staticRoutes_r->{$netWithMask} if exists $staticRoutes_r->{$netWithMask};

      my $gateway = $self->defaultGateway($iface);
      if (defined($gateway) and $gateway ne "") {
	$iflist{$iface}->{'gateway'} = $gateway;
      } else {
	$iflist{$iface}->{'gateway'} = $address;
      }
      my $search = $self->searchDomain($iface);
      $iflist{$iface}->{'search'} = $search;
      my $nameserver1 = $self->nameserver($iface,1);
      if (defined($nameserver1) and $nameserver1 ne "") {
	$iflist{$iface}->{'nameserver1'} = $nameserver1;
      }
      my $nameserver2 = $self->nameserver($iface,2);
      if (defined($nameserver2) and $nameserver2 ne "") {
	$iflist{$iface}->{'nameserver2'} = $nameserver2;
      }
      # NTP option
      my $ntpServer = $self->ntpServer($iface);
      if ( defined($ntpServer) and $ntpServer ne "") {
          $iflist{$iface}->{'ntpServer'} = $ntpServer;
      }
      # WINS/Netbios server option
      my $winsServer = $self->winsServer($iface);
      if ( defined($winsServer) and $winsServer ne "") {
          $iflist{$iface}->{'winsServer'} = $winsServer;
      }
      # Leased times
      my $defaultLeasedTime = $self->_leasedTime('default', $iface);
      if (defined($defaultLeasedTime)) {
        $iflist{$iface}->{'defaultLeasedTime'} = $defaultLeasedTime;
      }
      my $maxLeasedTime = $self->_leasedTime('max', $iface);
      if (defined($maxLeasedTime)) {
        $iflist{$iface}->{'maxLeasedTime'} = $maxLeasedTime;
      }
      # Thin client options
      my $nextServer = $self->_thinClientOption('nextServer', $iface);
      if ($nextServer) {
        $iflist{$iface}->{'nextServer'} = $nextServer;
      }
      my $filename = $self->_thinClientOption('filename', $iface);
      if (defined($filename)) {
        $iflist{$iface}->{'filename'} = $filename;
      }
      my $dynamicDomain = $self->_dynamicDNS('dynamic', $iface);
      if (defined($dynamicDomain)) {
          $iflist{$iface}->{'dynamicDomain'} = $dynamicDomain;
          $iflist{$iface}->{'staticDomain'}  = $self->_dynamicDNS('static', $iface);
      }
    }
  }

  return \%iflist;
}

# Method: _realIfaces
#
#    Get those interfaces which are real static ones containing the
#    virtual interfaces names which contain the real static interface
#
# Returns:
#
#    hash ref - containing interface name as key and an array ref
#    containing the virtual interface names as value
#
sub _realIfaces
{
  my ($self) = @_;
  my $net = EBox::Global->modInstance('network');

  my $real_ifaces = $net->ifaces();
  my %realifs;
  foreach my $iface (@{$real_ifaces}) {
    if ($net->ifaceMethod($iface) eq 'static') {
      $realifs{$iface} = $net->vifaceNames($iface);
    }

  }

  return \%realifs;
}

# Method: _areThereThinClientOptions
#
#    Check if there are thin client options in order to allow DHCP
#    server acting as a boot server by setting these options on the
#    configuration file
#
# Parameters:
#
#    ifacesInfo - hash ref every static interface is the key and the
#    value contains every single parameter required to be written on
#    the configuration file
#
# Returns:
#
#    Boolean - true if there are thin client options in at least one
#    iface, false otherwise
#
sub _areThereThinClientOptions
{
    my ($self, $ifacesInfo) = @_;

    foreach my $iface (keys %{$ifacesInfo}) {
        my $nextServer = $ifacesInfo->{$iface}->{'nextServer'};
        # Defined and non-zero strings
        if ( $nextServer ) {
            return 1;
        }
    }
    return 0;
}

# Method: _leasedTime
#
#    Get the leased time (default or maximum) in seconds if any
#
sub _leasedTime # (which, iface)
{
    my ($self, $which, $iface) = @_;

    my $advOptionsModel = $self->_getModel('leaseTimesModel', $iface);

    my $fieldName = $which . '_leased_time';
    return $advOptionsModel->row()->valueByName($fieldName);
}

# Method: _thinClientOption
#
#    Get the thin client option (nextServer or filename) if defined
#
sub _thinClientOption # (option, iface)
{

    my ($self, $option, $iface) = @_;

    my $thinClientModel = $self->_getModel('thinClientModel', $iface);

    if ( $option eq 'filename' ) {
        my $fileType = $thinClientModel->row()->elementByName('filename');
        if ( $fileType->exist() ) {
            # Write down the one stored in tftpd
            return EBox::DHCP->TftpdRootDir() . $iface . '_firmware';
        } else {
            my $file = $thinClientModel->row()->valueByName('remoteFilename');
            if( defined($file) and ($file ne '') ) {
                return $file;
            } else {
                return undef;
            }
        }
    } else {
        return $thinClientModel->nextServer();
    }

}

# Method: _dynamicDNS
#
#    Get the domains to be updated by DHCP server (dynamic or statics)
#
# Returns:
#
#    undef - if the dynamic DNS feature is not enabled
#
sub _dynamicDNS # (which, iface)
{
    my ($self, $which, $iface) = @_;

    my $dynamicDNSModel = $self->_getModel('dynamicDNSModel', $iface);

    my $dynamicOptionsRow = $dynamicDNSModel->row();
    if ( $dynamicOptionsRow->valueByName('enabled') ) {
        if ( $which eq 'dynamic' ) {
            return $dynamicOptionsRow->valueByName('dynamic_domain');
        } elsif ( $which eq 'static' ) {
            my $staticOption = $dynamicOptionsRow->elementByName('static_domain');
            if ( $staticOption->selectedType() eq 'same' ) {
                return $dynamicOptionsRow->valueByName('dynamic_domain');
            } elsif ( $staticOption->selectedType() eq 'custom' ) {
                return $dynamicOptionsRow->valueByName('static_domain');
            }
        }
    }
    return undef;

}

# Return the key file to update DNS
sub _keysFile
{
    my ($self) = @_;

    my $gl = EBox::Global->getInstance();
    if ( $gl->modExists('dns') ) {
        my $dnsMod = EBox::Global->modInstance('dns');
        if ( $dnsMod->configured() ) {
            return $dnsMod->keysFile();
        }
    }
    return '';

}

# Return if the dynamic DNS feature is enabled for this DHCP server or
# not given the iface list info
sub _dynamicDNSEnabled # (ifacesInfo)
{
    my ($self, $ifacesInfo) = @_;

    if ( defined($ifacesInfo) ) {
        my $nDynamicOptionsOn = grep { defined($ifacesInfo->{$_}->{'dynamicDomain'}) } keys %{$ifacesInfo};
        return ($nDynamicOptionsOn > 0);
    } else {
        my $net = EBox::Global->modInstance('network');
        my $ifaces = $net->allIfaces();
        foreach my $iface (@{$ifaces}) {
            if ( $net->ifaceMethod($iface) eq 'static' ) {
                my $mod = $self->_getModel('dynamicDNSModel', $iface);
                if ( $mod->row()->valueByName('enabled') ) {
                    return 1;
                }
            }
        }
        return 0;
    }
}


# Configure the firewall rules to add
# XXX maybe this is dead code?
sub _configureFirewall {
	my $self = shift;
	my $fw = EBox::Global->modInstance('firewall');
	try {
		$fw->removeOutputRule('udp', 67);
		$fw->removeOutputRule('udp', 68);
		$fw->removeOutputRule('tcp', 67);
		$fw->removeOutputRule('tcp', 68);
	} catch EBox::Exceptions::Internal with { };

	if ($self->isEnabled()) {
		$fw->addOutputRule('tcp', 67);
		$fw->addOutputRule('tcp', 68);
		$fw->addOutputRule('udp', 67);
		$fw->addOutputRule('udp', 68);
	}
}

# Returns those model instances attached to the given interface
sub _removeDataModelsAttached
{
    my ($self, $iface) = @_;

    # RangeTable/Options/FixedAddressTable
    foreach my $modelName (qw(leaseTimesModel thinClientModel optionsModel rangeModel fixedAddrModel)) {
        my $model = $self->_getModel($modelName, $iface);
        if ( defined ( $model )) {
            $model->removeAll(1);
        }
        $self->{$modelName}->{$iface} = undef;
    }
}

# Model getter, check if there are any model with the given
# description, if not, calling models again to create. Done until
# model provider works correctly with model method overriding models
# instead of modelClasses
sub _getModel
{
    my ($self, $modelName, $iface) = @_;

    unless ( exists $self->{$modelName}->{$iface} ) {
        $self->models();
    }
    return $self->{$modelName}->{$iface};

}

# Check there are enough static interfaces to have DHCP service enabled
sub _checkStaticIfaces
{
  my ($self, $adjustNumber) = @_;
  defined $adjustNumber or $adjustNumber = 0;

  my $nStaticIfaces = $self->_nStaticIfaces() + $adjustNumber;
  if ($nStaticIfaces == 0) {
    if ($self->isEnabled()) {
      $self->enableService(0);
      EBox::info('DHCP service was deactivated because there was not any static interface left');
    }
  }
}

# Return the current number of static interfaces
sub _nStaticIfaces
{
  my ($self) = @_;

  my $net = EBox::Global->modInstance('network');
  my $ifaces = $net->allIfaces();
  my $staticIfaces = grep  { $net->ifaceMethod($_) eq 'static' } @{$ifaces};

  return $staticIfaces;
}

# Method:  userConfDir
#
#  Returns:
#  path to the user configuration dir
sub userConfDir
{
  return CONF_DIR;
}

1;
