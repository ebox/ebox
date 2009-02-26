# Copyright (C) 2008 Warp Networks S.L.
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

package EBox::Module::Service;

#FIXME: as the only way to store stuff in gconf is to inherit from GConfModule
# we'll do it for now, but GConfModule has to go soon and the storage system
# reworked
use base qw(EBox::GConfModule);

use EBox::Global;
use EBox::Dashboard::ModuleStatus;
use EBox::Sudo;

use Error qw(:try);

use strict;
use warnings;

use constant INITDPATH => '/etc/init.d/';

# Method: usedFiles
#
#   This method is mainly used to show information to the user
#   about the files which are going to be modified by the service
#   managed  by eBox
#
# Returns:
#   
#   An array ref of hashes containing the following:
#
#       file - file's path
#       reason - some info about why you need to modify the file
#       module - module's name
#
#   Example:
#
#       [ 
#           { 
#             'file' => '/etc/samba/smb.conf',
#             'reason' =>  __('The file sharing module needs to modify it' .
#                           ' to configure samba properly')
#              'module' => samba 
#           }
#       ]
#
#
sub usedFiles 
{
    return [];
}

# Method: actions 
#
#   This method is mainly used to show information to the user
#   about the actions that need to be carried out by the service
#   to configure the system
#
# Returns:
#   
#   An array ref of hashes containing the following:
#
#       action - action to carry out
#       reason - some info about why you need to modify the file
#       module - module's name
#
#   Example:
#
#       [ 
#           { 
#             'action' => 'remove samba init script"
#             'reason' => 
#                   __('eBox will take care of start and stop the service')
#             'module' => samba 
#           }
#       ]
#
#
sub actions
{
    return [];
}

# Method: enableActions 
#
#   This method is run to carry out the actions that are needed to
#   enable a module. It usually executes those which are returned 
#   by actions.
#
#   For example: it could remove the samba init script
#
#
sub enableActions
{

}

# Method: disableActions
#
#   This method is run to rollbackthe actions that have been carried out
#   to enable a module.
#
#   For example: it could restore the samba init script
#
#
sub disableActions
{

}

# Method: enableModDepends 
#
#   This method is used to declare which modules need to be enabled
#   to use this module.
#
#   It doesn't state a configuration dependency, it states a working
#   dependency.
#
#   For example: the firewall module needs the network module.
#
#   By default it returns the modules established in the enabledepends list
#   in the module YAML file. Override the method if you need something more
#   specific, e.g., having a dynamic list.
#
# Returns:
#
#    array ref containing the dependencies.
#
#    Example:
#
#       [ 'firewall', 'users' ]
#
sub enableModDepends
{
    my ($self) = @_;
    my $depends = $self->info()->{'enabledepends'};
    if(not defined($depends)) {
        return [];
    } else {
        return $depends;
    }
}

# Method: configured 
#
#   This method is used to check if the module has been configured.
#   Configuration is done one time per service package version.
#
#   If this method returns true it means that the user has accepted
#   to carry out the actions and file modifications that enabling a
#   service implies.
#
#   If you must store this value in the status branch of gconf in case
#   you decide to override it.
#
# Returns:
#
#   boolean 
#
sub configured 
{
    my ($self) = @_;

    if ((@{$self->usedFiles()} + @{$self->actions()}) == 0) {
        return 1;
    }

    unless ($self->st_get_bool('_serviceConfigured')) {
        return undef; 
    }

    return $self->st_get_bool('_serviceConfigured');
}

# Method: setConfigured 
#
#   This method is used to set if the module has been configured.
#   Configuration is done one time per service package version.
#
#   If it's set to true it means that the user has accepted
#   to carry out the actions and file modifications that enabling a
#   service implies.
#
#   If you must store this value in the status branch of gconf in case
#   you decide to override it.
#
# Parameters:
#
#   boolean - true if configured, false otherwise
#
sub setConfigured 
{
    my ($self, $status) = @_;

    return unless ($self->configured() xor $status);
    return $self->st_set_bool('_serviceConfigured', $status);
}


# Method: isEnabled
#
#   Used to tell if a module is enabled or not
#
# Returns:
#
#   boolean 
sub isEnabled
{
    my ($self) = @_;

    unless ($self->get_bool('_serviceModuleStatus')) {
        return $self->defaultStatus();
    }

    return $self->get_bool('_serviceModuleStatus');
}

# Method: _isDaemonRunning
#
#   Used to tell if a daemon is running or not
#
# Returns:
#
#   boolean - true if it's running otherwise false
sub _isDaemonRunning
{
    my ($self, $dname) = @_;
    my $daemons = $self->_daemons();

    my $daemon;
    my @ds = grep { $_->{'name'} eq $dname } @{$daemons};
    if(@ds) {
        $daemon = $ds[0];
    }
    if(!defined($daemon)) { 
        throw EBox::Exceptions::Internal(
            "no such daemon defined in this module: " . $dname);
    }
    if(defined($daemon->{'pidfile'})) {
        my $pidfile = $daemon->{'pidfile'};
        return $self->pidFileRunning($pidfile);
    }
    if(daemon_type($daemon) eq 'upstart') {
        return EBox::Service::running($dname);
    } elsif(daemon_type($daemon) eq 'init.d') {
        my $output;
        my $notOk;
        try {
            $output = EBox::Sudo::root(INITDPATH .
                $dname . ' ' . 'status');
        } catch EBox::Exceptions::Sudo::Command with {
            # Command returned != 0
            $notOk = 1;
        };
        if ($notOk) {
            return 0;
        }
        my $status = @{$output}[0];
        if ($status =~ m{$dname .* running}) {
            return 1;
        } else {
            return 0;
        }
    } else {
        throw EBox::Exceptions::Internal(
            "Service type must be either 'upstart' or 'init.d'");
    }
}

# Method: isRunning
#
#   Used to tell if a service is running or not.
#
#   Modules with complex service management must
#   override this method to carry out their custom checks which can
#   involve checking an upstart script, an existing PID...
#
#   By default it returns true if all the system services specified in 
#   daemons are running
#
# Returns:
#
#   boolean - true if it's running otherwise false
sub isRunning
{
    my ($self) = @_;

    my $daemons = $self->_daemons();
    for my $daemon (@{$daemons}) {
        my $check = 1;
        my $pre = $daemon->{'precondition'};
        if(defined($pre)) {
            $check = $pre->($self);
        }
        $check or next;
    }
    return 1;
}

# Method: addModuleStatus
#
#   Called by the sysinfo module status widget to give the desired information
#   about the current module status. This default implementation should be ok
#   for most modules but it can be overriden to provide a custom one (or none).
#
# Parameters:
#
#   section - the section the information is added to
#
sub addModuleStatus
{
    my ($self, $section) = @_;
    my $enabled = $self->isEnabled();
    my $running = $self->isRunning();
    my $name = $self->name();
    my $modPrintName = ucfirst($self->printableName());
    $section->add(new EBox::Dashboard::ModuleStatus(
        module        => $name,
        printableName => $modPrintName,
        enabled       => $enabled,
        running       => $running,
        nobutton      => not $self->_supportActions()
       ));
}

# Method: enableService
#
#   Used to enable a service
#
# Paramters:
#
#   boolean - true to enable, false to disable
#
sub enableService
{
    my ($self, $status) = @_;

    return unless ($self->isEnabled() xor $status);

    $self->set_bool('_serviceModuleStatus', $status);
}

# Method: defaultStatus
#
#   This method must be overriden if you want to enable the service by default
#
# Returns:
#
#   boolean
sub defaultStatus 
{
    return undef;
}

sub daemon_type
{
    my ($daemon) = @_;
    if($daemon->{'type'}) {
        return $daemon->{'type'};
    } else {
        return 'upstart';
    }
}

# Method: showModuleStatus
#
#   Indicate to ServiceManager if the module must be shown in Module
#   status configuration.
#
#   It must be overridden in rare cases
#
# Returns:
#
#   true
#
sub showModuleStatus
{
    return 1;
}

# Method: _daemons
#
#   This method must be overriden to return the services required by this
#   module.
#
# Returns:
#
#   An array of hashes containing keys 'name' and 'type', 'name' being the
#   name of the service and 'type' either 'upstart' or 'init.d', depending
#   on how the module should be managed.
#
#   If the type is 'init.d' an extra 'pidfile' key is needed with the path
#   to the pidfile the daemon uses. This will be used to check the status.
#
#   It can optionally contain a key 'precondition', which should be a reference
#   to a class method which will be checked to determine if the given daemon
#   should be run (if it returns true) or not (otherwise).
#
#   Example:
#
#   sub externalConnection
#   {
#     my ($self) = @_;
#     return $self->isExternal;
#   }
#
#   sub _daemons
#   {
#    return [
#        {
#            'name' => 'ebox.jabber.jabber-router',
#            'type' => 'upstart'
#        },
#        {
#            'name' => 'ebox.jabber.jabber-resolver',
#            'type' => 'upstart',
#            'precondition' => \&externalConnection
#        }
#    ];
#   }
sub _daemons
{
    return [];
}

sub _startDaemon
{
    my($self, $daemon) = @_;
    if(daemon_type($daemon) eq 'upstart') {
        if(EBox::Service::running($daemon->{'name'})) {
            EBox::Service::manage($daemon->{'name'},'restart');
        } else {
            EBox::Service::manage($daemon->{'name'},'start');
        }
    } elsif(daemon_type($daemon) eq 'init.d') {
        my $pidfile = $daemon->{'pidfile'};
        if(!defined($pidfile)) {
            throw EBox::Exceptions::Internal(
                "init.d-based daemons must include a 'pidfile'");
        }
        my $script = INITDPATH . $daemon->{'name'};
        if($self->pidFileRunning($pidfile)) {
            $script = $script . ' ' . 'restart';
        } else {
            $script = $script . ' ' . 'start';
        }
        EBox::Sudo::root($script);
    } else {
        throw EBox::Exceptions::Internal(
            "Service type must be either 'upstart' or 'init.d'");
    }
}

sub _stopDaemon
{
    my($self, $daemon) = @_;
    if(daemon_type($daemon) eq 'upstart') {
        EBox::Service::manage($daemon->{'name'},'stop');
    } elsif(daemon_type($daemon) eq 'init.d') {
        my $script = INITDPATH . $daemon->{'name'} . ' ' . 'stop';
        EBox::Sudo::root($script);
    } else {
        throw EBox::Exceptions::Internal(
            "Service type must be either 'upstart' or 'init.d'");
    }
}

# Method: _manageService
#
#   This method will try to perform the action passed as first argument on 
#   all the daemons return by the module's daemons method.
#
sub _manageService
{
    my ($self,$action) = @_;

    my $daemons = $self->_daemons();
    for my $daemon (@{$daemons}) {
        my $run = 1;
        my $pre = $daemon->{'precondition'};
        if(defined($pre)) {
            $run = &$pre($self);
        }
        #even if parameter is 'start' we might have to stop some daemons
        #if they are no longer needed
        if(($action eq 'start') and $run) {
            $self->_startDaemon($daemon);
        } else {
            $self->_stopDaemon($daemon);
        }
    }
}

# Method: _startService
#
#   This method will try to start or restart all the daemons associated to
#   the module
#
sub _startService
{
    my ($self) = @_;
    $self->_manageService('start');
}

# Method: stopService
#
#   This is the external interface to call the implementation which lies in
#   _stopService in subclassess
#
#
sub stopService
{
    my $self = shift;

    $self->_lock();
    try {
        $self->_stopService();
    } finally {
        $self->_unlock();
    };
}

# Method: _stopService
#
#   This method will try to stop all the daemons associated to the module
#
sub _stopService
{
    my ($self) = @_;
    $self->_manageService('stop');
}

# Method: _regenConfig
#
#	Base method to regenerate configuration. It should be overriden
#	by subclasses as needed
#
sub _regenConfig 
{
    my ($self) = @_;

    $self->_setConf();
    $self->_enforceServiceState();
}

# Method: restartService
#
#        This method will try to restart the module's service by means of
#        calling _regenConfig. The method call has the named
#        parameter restart with true value
#
sub restartService
{
	my $self = shift;

	$self->_lock();
	my $global = EBox::Global->getInstance();
	my $log = EBox::logger;

	if (not $self->isEnabled()) {
		$log->info("Skipping restart for $self->{name} as it's disabled");
		return;
	}

	$log->info("Restarting service for module: " . $self->name);
	try {
            $self->_regenConfig('restart' => 1);
	} otherwise  {
            my ($ex) = @_;
            $log->error("Error restarting service: $ex");
            throw $ex;
        } finally {
		$self->_unlock();
	};
}

# Method: _supportActions
#
#   This method determines if the service will have a button to start/restart
#   it in the module status widget. By default services will have the button
#   unless this method is overriden to return undef
sub _supportActions
{
    return 1;
}

# Method: _enforceServiceState
#
#   This method will start, restart or stop the associated daemons to 
#   bring them to their desired state
#
sub _enforceServiceState
{
    my ($self) = @_;
    if($self->isEnabled()) {
        $self->_startService();
    } else {
        $self->_stopService();
    }
}

#
# Method: writeConfFile
#
#    It executes a given mason component with the passed parameters over 
#    a file. It becomes handy to set configuration files for services. 
#    Also, its file permissions will be kept.
#    It can be called as class method. (XXX: this design or is an implementation accident?)
#    XXX : the correct behaviour will be to throw exceptions if file will not be stated and no defaults are provided. It will provide hardcored defaults instead because we need to be backwards-compatible
#
#
# Parameters:
#
#    file      - file name which will be overwritten with the execution output
#    component - mason component
#    params    - parameters for the mason component. Optional. Defaults to no parameters
#    defaults  - a reference to hash with keys mode, uid and gid. Those values will be used when creating a new file. (If the file already exists the existent values of these parameters will be left untouched)
#
sub writeConfFile # (file, component, params, defaults)
{
    my ($self, $file, $compname, $params, $defaults) = @_;

    # we will avoid check modification when the method is called as class method
    #  this is awkward but is the fudge we had used to date for files created
    #  by ebox which rhe user shoudn't give their permission to modify
    #   maybe we need to add some parameter to better reflect this?

    my $manager;

    $manager = new EBox::ServiceManager();
    if ($manager->skipModification($self->{'name'}, $file)) {
        EBox::info("Skipping modification of $file");
        return;
    }

    EBox::Module::Base::writeConfFileNoCheck($file, $compname, $params, $defaults);

    $manager->updateFileDigest($self->{'name'}, $file);
}

1;
