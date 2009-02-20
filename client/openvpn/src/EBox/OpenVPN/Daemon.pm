package EBox::OpenVPN::Daemon;

# package: Parent class for the distinct types of OpenVPN daemons
use strict;
use warnings;

use base qw(EBox::NetworkObserver);

use File::Slurp;
use Error qw(:try);

use EBox::NetWrappers;
use EBox::Service;

use constant UPSTART_DIR => '/etc/event.d';

sub new
{
    my ($class, $row) = @_;

    my $self = {};
    $self->{row}  = $row;

    bless $self, $class;

    return $self;
}

sub _openvpnModule
{
    my ($self) = @_;
    return EBox::Global->modInstance('openvpn');
}

#
# Method: init
#
#   Must be implimented by child to do initalisation stuff
#
#  Parametes:
#        $name        - the name of the daemon
#        @params      - initialization parameters, may be different for each daemon type
#
sub init
{
    throw EBox::Exceptions::NotImplemented('init method');
}

#
# Method: name
#
#  Returns:
#    the name of the daemon
sub name
{
    my ($self) = @_;
    return $self->_rowAttr('name');
}

sub type
{
    throw EBox::Exceptions::NotImplemented('type class method');
}

sub service
{
    my ($self) = @_;
    return $self->_rowAttr('service');
}

sub _rowAttr
{
    my ($self, $name) = @_;

    my $element = $self->{row}->elementByName($name);
    return $element->value();
}

sub _configAttr
{
    my ($self, $name) = @_;

    my $config =
      $self->{row}->elementByName('configuration')->foreignModelInstance();

    return $config->$name();
}

#
# Method: upstartName
#
#  Returns:
#    the name of the upstart service that controls the daemon
sub upstartName
{
    my ($self)  = @_;
    return __PACKAGE__->upstartNameForDaemon($self->name, $self->type);
}

#
# Method: upstartNameForDaemon
#
#  Parameters:
#
#    $type  - daemon's type
#    $name  - daemons's ma,e
#
#  Returns:
#    the name of the upstart service for the daemon type and name given
sub upstartNameForDaemon
{
    my ($class, $name, $type) = @_;
    $type
      or throw EBox::Exceptions::MissingArgument('type');
    $name
      or throw EBox::Exceptions::MissingArgument('name');

    return 'ebox.openvpn.' . $type . '.' . $name;
}

sub _upstartFile
{
    my ($self) = @_;
    return  UPSTART_DIR . '/' . $self->upstartName();
}

sub _upstartFileForDaemon
{
    my ($class, $name, $type) = @_;
    return  UPSTART_DIR . '/' . $class->upstartNameForDaemon($name, $type);
}

sub ifaceNumber
{
    my ($self) = @_;
    return $self->_rowAttr('interfaceNumber');
}

#
# Method: iface
#
#   get the iface device name used for this daemon
#
# Returns:
#    - the device name
sub iface
{
    my ($self) = @_;

    my $ifaceType = $self->ifaceType();
    my $number    = $self->ifaceNumber();
    return "$ifaceType$number";
}

#
# Method: ifaceType
#
#   get the iface device type used for this daemon
#
# Returns:
#    - the device type
sub ifaceType
{
    my ($self) = @_;
    return $self->_rowAttr('interfaceType');
}

#
# Method: ifaceAddress
#
#   get the vpn's iface address
#
# Returns:
#    - the address in CIDR notation or undef if the interface has not address
sub ifaceAddress
{
    my ($self) = @_;
    my $iface = $self->iface();

    if (not EBox::NetWrappers::iface_exists($iface)) {
        return undef;
    }

    if (not EBox::NetWrappers::iface_is_up($iface)) {
        return undef;
    }

    my %addresses =
      %{ EBox::NetWrappers::iface_addresses_with_netmask($iface) };
    my $nAddresses = keys %addresses;
    if ($nAddresses == 0) {
        EBox::error("No address found for interface $iface");
        return undef;
    }elsif ($nAddresses > 1) {
        EBox::warn(
"More than one addres for interface $iface. Only one of them will be show" );
    }

    my ($addr, $netmask) = each %addresses;
    my $cidrAddr = EBox::NetWrappers::to_network_with_mask($addr, $netmask);

    return $cidrAddr;
}

#
# Method: user
#
#    Return the user will be used to run the  daemon
#    after root drops privileges
#  Returns:
#    string - the user which will be run the daemon after the initialization
sub user
{
    my ($self) = @_;
    return $self->_openvpnModule->user();
}

# Method: group
#
#    Return the user will be used to run the  daemon
#    after root drops privileges
#
#  Returns:
#    string - the group which will be run the daemon after the initialization
sub group
{
    my ($self) = @_;
    return $self->_openvpnModule->group();
}

#
# Method: dh
#
#  Returns:
#    the diffie-hellman parameters file used by the daemon
sub dh
{
    my ($self) = @_;
    return $self->_openvpnModule->dh();
}

sub logFile
{
    my ($self) = @_;
    return $self->_logFile('');
}

sub statusLogFile
{
    my ($self) = @_;
    return $self->_logFile('status-');
}

sub _logFile
{
    my ($self, $prefix) = @_;
    my $logDir = $self->_openvpnModule->logDir();
    my $file = $logDir . "/$prefix"  . $self->name() . '.log';
    return $file;
}

# Method: internal
#
#   tell wether the client must been internal for users in the UI or nodaemon
#   is a internal daemon used and created by other EBox services
#
# Returns:
#  returns the daemon's internal state
sub internal
{
    throw EBox::Exceptions::NotImplemented(
                                          'Must be immplemented in subclasses');
}

#
# Method: confFile
#
#   get the configuration file for this daemon
#
#  Parameters:
#     confDir - directory where the configuration file will be stored
#
# Returns:
#    - the path of the configuration file
sub confFile
{
    my ($self, $confDir) = @_;
    my $name = $self->name();

    return __PACKAGE__->confFileForName($name, $confDir);
}

sub confFileForName
{
    my ($package, $name, $confDir) = @_;
    defined $confDir
      or throw EBox::Exceptions::MissingArgument('confDir');
    defined $name
      or throw EBox::Exceptions::MissingArgument('name');

    my $confFile = $name . '.conf';
    my $confFilePath = defined $confDir ? "$confDir/$confFile" : $confFile;

    return $confFilePath;
}

#
# Method: writeConfFile
#
#   write the daemon's configuration file
#
#  Parameters:
#     confDir - directory where the configuration file will be stored
#
sub writeConfFile
{
    my ($self, $confDir) = @_;

    return if not $self->service();

    my $confFilePath   = $self->confFile($confDir);
    my $templatePath   = $self->confFileTemplate();
    my $templateParams = $self->confFileParams();

    push @{$templateParams},
      (
        logFile       => $self->logFile(),
        statusLogFile => $self->statusLogFile(),
      );

    my $fileAttrs  = {
                      uid  => 0,
                      gid  => 0,
                      mode => '0400',
    };

    EBox::Module::Base::writeConfFileNoCheck(
        $confFilePath, $templatePath,
        $templateParams, $fileAttrs
    );
}

#
# Method: confFileTemplate
#
#   Abstract method. Must return the configuration file template
#
# Returns:
#   the mason path of the configuration file template
sub confFileTemplate
{
    throw EBox::Exceptions::NotImplemented();
}

#
# Method: daemonFiles
#
#    Get a list with the files and directories generated by the given
#    daemon. Paths must be absolute. Directories contents are not included
#
#    This is a default implementation, specifics daemon classes may want to
#    override this to include their additional files
#
#  Parameters:
#        $name - daemon name
#
# Returns:
#  a list with each path as string
sub daemonFiles
{
    my ($class, $name) = @_;

    my $confDir  = $class->_openvpnModule->confDir();
    my $confFile = $class->confFileForName($name, $confDir);

    return ($confFile);
}

#
# Method: confFileParams
#
#   Abstract method. Must return the configuration file template parameters
#
# Returns:
#   a reference to the parameter's list
sub confFileParams
{
    throw EBox::Exceptions::NotImplemented();
}

#
# Method: ripDaemon
#
#   Abstract method. Must return the configuration file template
#
#
# Returns:
#   undef if no ripDaemon is needed by the openvpn's daemon
#   if the ripDaemons is needed it must return a hash refrence with the
#   following keys:
#       iface        - a hash ref returned from the method ifaceWithRipPasswd
#       redistribute - wether the daemon wants to redistribute routes or not
sub ripDaemon
{
    throw EBox::Exceptions::NotImplemented();
}

#   Method: ifaceWithRipPasswd
#
#  return a reference to a hash with the interface information needed to
#  configure the ripd daemon
#
#   Returns:
#        hash reference with the following fields
#              ifaceName - name of the network interface
#              passwd    - rip password for this daemon
sub ifaceWithRipPasswd
{
    my ($self) = @_;
    my $iface = $self->iface;
    my $passwd = $self->ripPasswd;

    return {
            ifaceName => $iface,
            passwd    => $passwd,
    };
}

#  Method: ripPasswd
#
#     get the password used by this daemon to secure RIP transmissions
#
#     Returns:
#        the password as string (empty string if the password wasn't set)
sub ripPasswd
{
    my ($self) = @_;
    my $passwd = $self->_configAttr('ripPasswd');
    defined $passwd or $passwd = '';   # in some cases it may be optional it may
    # be undefined
    return $passwd;
}

#  Method: setRipPasswd
#
#     set the password used by this daemon to secure RIP transmissions
#
#     Parameters:
#        passwd - string
sub setRipPasswd
{
    my ($self, $passwd) = @_;
    throw EBox::Exceptions::NotImplemented('setRipPasswd');
}

# Method: start
#
#  Start the daemon
sub start
{
    my ($self) = @_;
    EBox::Service::manage($self->upstartName, 'start');
}

#
# Method: stop
#
#  Stop the daemon
sub stop
{
    my ($self) = @_;
    EBox::Service::manage($self->upstartName, 'stop');
}

sub stopDeletedDaemon
{
    my ($class, $name, $type) = @_;

    $class->isa('EBox::OpenVPN::Daemon')
      or throw EBox::Exceptions::Internal(
                                      "$class is not a openvpn's daemon class");

    # see if we have upstart service
    my $upstartFile = $class->_upstartFileForDaemon($name, $type);
    if (not -f $upstartFile) {
        return;

    }

    my $upstartService = $class->upstartNameForDaemon($name, $type);
    EBox::Service::manage($upstartService, 'stop');

    $class->removeUpstartFileForDaemon($name, $type);
}

sub deletedDaemonCleanup
{
    my ($class, $name) = @_;
    my $type = $class->type();

    try {
        $class->stopDeletedDaemon($name, $type);

        foreach my $file  ( $class->daemonFiles($name) ) {
            EBox::Sudo::root(" rm -rf $file");

        }
    }
    otherwise {
        my $ex = shift;
        EBox::error(
"Failure when cleaning up the deleted openvpn daemon $name. Possibly you will need to do some manual cleanup"
        );
        $ex->throw();
    };
}

sub _rootCommandForStartDaemon
{
    my ($self) = @_;

    my $name    = $self->name;
    my $bin     = $self->_openvpnModule->openvpnBin();
    my $confDir = $self->_openvpnModule->confDir();
    my $confFilePath =   $self->confFile($confDir);
    my $pidFile = $self->_pidFile();

    return "$bin  --syslog $name  --config $confFilePath";
}

sub _pidFile
{
    my ($self) = @_;
    return '/var/run/openvpn.' . $self->name . '.pid';

}

#
# Method: pid
#
# Returns:
#     the pid of the daemon or undef if isn't running
sub pid
{
    my ($self) = @_;
    my $pid;

    try {
        $pid = File::Slurp::read_file($self->_pidFile);

    }
    otherwise {
        $pid = undef;
    };

    return $pid;
}

#
# Method: running
#
# Returns:
#    bool - wether the daemon is running
sub running
{
    my ($self) = @_;

    if (not -f $self->_upstartFile()) {
        return undef;
    }

    return EBox::Service::running($self->upstartName);
}

sub writeUpstartFile
{
    my ($self) = @_;

    my $path = $self->_upstartFile();
    my $cmd  = $self->_rootCommandForStartDaemon();

    my $fileAttrs    = {
                        uid  => 0,
                        gid  => 0,
                        mode => '0644',
    };

    EBox::Module::Base::writeConfFileNoCheck(
        $path,'/openvpn/upstart.mas',
        [ cmd => $cmd],$fileAttrs
       );

}

sub removeUpstartFile
{
    my ($self) = @_;

    my $path = $self->_upstartFile();
    EBox::Sudo::root("rm -f $path");
}

sub removeUpstartFileForDaemon
{
    my ($class, $name, $type) = @_;
    $type
      or throw EBox::Exceptions::MissingArgument('type');
    $name
      or throw EBox::Exceptions::MissingArgument('name');

    my $path = $class->_upstartFileForDaemon($name, $type);
    EBox::Sudo::root("rm -f $path");
}

#
# Method: summary
#
#   Abstract method. May be implemented by any daemon which wants his summary section
#
# Returns:
#     the summary data as list; the first element will be the title of the summary
#     section and the following pairs will be usd to build EBox::Summary::Value objects
sub summary
{
    my ($self) = @_;
    return ();
}

1;
