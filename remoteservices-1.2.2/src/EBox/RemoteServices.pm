# Copyright (C) 2007 Warp Networks S.L.
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

package EBox::RemoteServices;

# Class: EBox::RemoteServices
#
#      RemoteServices module to handle everything related to the remote
#      services offered
#
use base qw(EBox::Module::Service
            EBox::Model::ModelProvider
            EBox::Model::CompositeProvider
           );

use strict;
use warnings;

use Error qw(:try);

# eBox uses
use EBox::Config;
use EBox::Dashboard::ModuleStatus;
use EBox::Exceptions::External;
use EBox::Exceptions::Internal;
use EBox::Gettext;
use EBox::Global;
use EBox::Service;
use EBox::RemoteServices::Backup;
use EBox::RemoteServices::Subscription;
use EBox::Sudo;

# Constants
use constant SERV_DIR            => EBox::Config::conf() . 'remoteservices/';
use constant CA_DIR              => SERV_DIR . 'ssl-ca/';
use constant SUBS_DIR            => SERV_DIR . 'subscription/';
use constant WS_DISPATCHER       => __PACKAGE__ . '::WSDispatcher';
use constant RUNNERD_SERVICE     => 'ebox.runnerd';
use constant SITE_HOST_KEY       => 'siteHost';

# Group: Protected methods

# Constructor: _create
#
#        Create an event module
#
# Overrides:
#
#        <EBox::GConfModule::_create>
#
# Returns:
#
#        <EBox::Events> - the recently created module
#
sub _create
{

    my $class = shift;

    my $self = $class->SUPER::_create( name => 'remoteservices',
                                       domain => 'ebox-remoteservices',
                                       printableName => __('Control Center Client'),
                                       @_
                                      );

    bless ($self, $class);

    return $self;

}

# Method: domain
#
# Overrides:
#
#        <EBox::Module::domain>
#
sub domain
{
    return 'ebox-remoteservices';
}

# Method: _setConf
#
#        Regenerate the configuration for the remote services module
#
# Overrides:
#
#       <EBox::Module::Service::_setConf>
#
sub _setConf
{

      my ($self) = @_;

      $self->_confSOAPService();
      $self->_establishVPNConnection();

}

# Method: _daemons
#
# Overrides:
#
#       <EBox::Module::Service::_daemons>
#
sub _daemons
{
    return [
        {
            'name'         => RUNNERD_SERVICE,
            'precondition' => \&eBoxSubscribed,
        }
       ];
}

# Method: isEnabled
#
#       Module is enabled only when the subscription is done
#
# Overrides:
#
#       <EBox::Module::Service::isEnabled>
#
sub isEnabled
{
    my ($self) = @_;

    return $self->eBoxSubscribed();

}

# Group: Public methods

# Method: addModuleStatus
#
# Overrides:
#
#       <EBox::Module::Service::addModuleStatus>
#
sub addModuleStatus
{
    my ($self, $section) = @_;

    my $subscriptionStatus = __('Not subscribed');
    if ( $self->eBoxSubscribed() ) {
        $subscriptionStatus = __('Subscribed');
    }

    $section->add(new EBox::Dashboard::ModuleStatus(
        module        => $self->name(),
        printableName => $self->printableName(),
        nobutton      => 1,
        statusStr     => $subscriptionStatus));
}

# Method: showModuleStatus
#
# Overrides:
#
#       <EBox::Module::Service::showModuleStatus>
#
sub showModuleStatus
{
    return 0;
}

# Method: menu
#
# Overrides:
#
#       <EBox::Module::menu>
#
sub menu
{
    my ($self, $root) = @_;
    $root->add(new EBox::Menu::Item('url'  => 'RemoteServices/Composite/General',
                                    'name' => 'Subscription',
                                    'text' => __('Control Center'),
                                    'order' => 80,
                                   )
              );
}

# Method: modelClasses
#
#       Return the model classes used by events eBox module
#
# Overrides:
#
#       <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{

    my ($self) = @_;

    return [
        'EBox::RemoteServices::Model::Subscription',
        'EBox::RemoteServices::Model::AccessSettings',
       ];

}

# Method: compositeClasses
#
# Overrides:
#
#    <EBox::Model::CompositeProvider::compositeClasses>
#
sub compositeClasses
{
    my ($self) = @_;

    return [ 'EBox::RemoteServices::Composite::General' ];
}

# Method: eBoxSubscribed
#
#        Test if current eBox is subscribed to remote services
#
# Returns:
#
#        true - if the current eBox is subscribed
#
#        false - otherwise
#
sub eBoxSubscribed
{
    my ($self) = @_;

    return $self->model('Subscription')->eBoxSubscribed();

}

# Method: unsubscribe
#
#        Delete every data related to the eBox subscription and stop any
#        related service associated with it
#
# Returns:
#
#        True  - if the eBox is subscribed and now it is not
#
#        False - if the eBox was not subscribed before
#
sub unsubscribe
{
    my ($self) = @_;

    return $self->model('Subscription')->unsubscribe();

}

# Method: eBoxCommonName
#
#        The common name to be used as unique which is subscribed by
#        this eBox. It has sense only when
#        <EBox::RemoteServices::eBoxSubscribed> returns true.
#
# Returns:
#
#        String - the subscribed eBox common name
#
#        undef - if <EBox::RemoteServices::eBoxSubscribed> returns
#        false
#
sub eBoxCommonName
{
    my ($self) = @_;

    if ( $self->eBoxSubscribed() ) {
        return $self->model('Subscription')->eboxCommonNameValue();
    } else {
        return undef;
    }

}

# Method: subscriberUsername
#
#        The subscriber's user name. It has sense only when
#        <EBox::RemoteServices::eBoxSubscribed> returns true.
#
# Returns:
#
#        String - the subscriber user name
#
#        undef - if <EBox::RemoteServices::eBoxSubscribed> returns
#        false
#
sub subscriberUsername
{
    my ($self) = @_;

    if ( $self->eBoxSubscribed() ) {
        return $self->model('Subscription')->usernameValue();
    } else {
        return undef;
    }

}

# Method: controlPanelURL
#
#        Return the control panel fully qualified URL to access
#        control panel
#
# Returns:
#
#        String - the control panel URL
#
# Exceptions:
#
#        <EBox::Exceptions::External> - thrown if the URL cannot be
#        found in configuration files
#
sub controlPanelURL
{
    my $url =  EBox::RemoteServices::Auth->new()->valueFromBundle(SITE_HOST_KEY);
    return "https://${url}/"
}

# Method: ifaceVPN
#
#        Return the virtual VPN interface for the secure connection
#        between this eBox and remote services
#
# Return:
#
#        String - the interface name
#
sub ifaceVPN
{
    my ($self) = @_;

    my $authRS = new EBox::RemoteServices::Backup();
    my $vpnClient = $authRS->vpnClientForServices();
    return $vpnClient->iface();

}

# Method: vpnSettings
#
#        Return the virtual VPN settings for the secure connection
#        between this eBox and remote services
#
# Return:
#
#        hash ref - containing the two following elements
#
#             ipAddr - String the VPN IP address
#             port   - Int the port to connect to
#             protocol - String the protocol associated to that port
#
sub vpnSettings
{
    my ($self) = @_;

    my $authRS = new EBox::RemoteServices::Backup();
    my ($ipAddr, $port, $protocol) = @{$authRS->vpnLocation()};

    return { ipAddr => $ipAddr,
             port => $port,
             protocol => $protocol };

}

# Group: Private methods

# Configure the SOAP server
#
# if subscribed
# 1. Write soap-loc.mas template
# 2. Write the SSLCACertificatePath directory
# 3. Add include in ebox-apache configuration
# else
# 1. Remove SSLCACertificatePath directory
# 2. Remove include in ebox-apache configuration
#
sub _confSOAPService
{
    my ($self) = @_;

    my $confFile = SERV_DIR . 'soap-loc.conf';
    my $apacheMod = EBox::Global->modInstance('apache');
    if ($self->eBoxSubscribed()) {
        my @tmplParams = (
            (soapHandler      => WS_DISPATCHER),
            (domainName       => $self->_confKeys()->{domain}),
            (allowedClientCNs => $self->_allowedClientCNRegexp()),
            (confDirPath      => EBox::Config::conf()),
            (caPath           => CA_DIR),
           );
        EBox::Module::Base::writeConfFileNoCheck(
            $confFile,
            'remoteservices/soap-loc.mas',
            \@tmplParams);
        unless ( -d CA_DIR ) {
            mkdir(CA_DIR);
        }
        my $caLinkPath = $self->_caLinkPath();
        if ( -l $caLinkPath ) {
            unlink($caLinkPath);
        }
        symlink($self->_caCertPath(), $caLinkPath );

        $apacheMod->addInclude($confFile);
    } else {
        unlink($confFile);
        # Remove CA_DIR
        opendir(my $dir, CA_DIR);
        while(my $file = readdir($dir)) {
            # Check if it is a symbolic link file to remove it
            next unless (-l CA_DIR . $file);
            unlink(CA_DIR . $file);
        }
        closedir($dir);
        try {
            $apacheMod->removeInclude($confFile);
        } catch EBox::Exceptions::Internal with {
            # Do nothing if it's already remove
            ;
        };
    }
    $apacheMod->save();

}

# Assure the VPN connection with our VPN servers is established
sub _establishVPNConnection
{
    my ($self) = @_;

    if ( $self->eBoxSubscribed() ) {
        try {
            my $authConnection = new EBox::RemoteServices::Backup();
            $authConnection->connection();
        } catch EBox::Exceptions::External with {
            my ($exc) = @_;
            EBox::error("Cannot contact to Control Center: $exc");
        };
    }

}

# Return the allowed client CNs regexp
sub _allowedClientCNRegexp
{
    my ($self) = @_;

    my $mmProxy  = $self->_confKeys()->{managementProxy};
    my $wwwProxy = $self->_confKeys()->{wwwServiceProxy};
    my ($mmPrefix, $mmRem) = split(/\./, $mmProxy, 2);
    my ($wwwPrefix, $wwwRem) = split(/\./, $wwwProxy, 2);
    my $nums = '[0-9]+';
    return "^(${mmPrefix}$nums.${mmRem}|${wwwPrefix}$nums.${wwwRem})\$";
}

# Return the given configuration file from the control center
sub _confKeys
{
    my ($self) = @_;

    unless ( defined($self->{confFile}) ) {
        my $confDir = SUBS_DIR . $self->eBoxCommonName();
        $self->{confFile} = (<$confDir/*.conf>)[0];
    }
    unless ( defined($self->{confKeys}) ) {
        $self->{confKeys} = EBox::Config::configKeysFromFile($self->{confFile});
    }
    return $self->{confKeys};
}

# Return the CA cert path
sub _caCertPath
{
    my ($self) = @_;

    return SUBS_DIR . $self->eBoxCommonName() . '/cacert.pem';

}

# Return the link name for the CA certificate in the given format
# hashValue.0 - hash value is the output from openssl ciphering
sub _caLinkPath
{
    my ($self) = @_;

    my $caCertPath = $self->_caCertPath();
    my $hashRet = EBox::Sudo::command("openssl x509 -hash -noout -in $caCertPath");

    my $hashValue = $hashRet->[0];
    chomp($hashValue);
    return CA_DIR . "${hashValue}.0";

}

1;
