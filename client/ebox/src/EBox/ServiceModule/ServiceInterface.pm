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

# Class: EBox::ConfigurationFile::ServiceInterface
#
#   This class is meant to be used by those modules which are going
#   to modify configuration files
#
#   FIXME:
#
#   Among others: provide a method to set a default status
package EBox::ServiceModule::ServiceInterface;

use EBox::Global;

use strict;
use warnings;


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
    return [];
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


    my $gconf = $self->_gconfModule();
    unless (defined($gconf)) {
        throw EBox::Exceptions::Internal(
            "EBox::ServiceModule::ServiceInterface:configured() must be " .
            " overriden or " .
            " EBox::Serice::Module::ServiceInterface::serviceModuleName must " .
            " return a valid gconf module");
    }

    if ($gconf->st_get_bool('_serviceConfigured') eq '') {
        return undef; 
    }

    return $gconf->st_get_bool('_serviceConfigured');
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

    my $gconf = $self->_gconfModule();
    unless (defined($gconf)) {
        throw EBox::Exceptions::Internal(
            "EBox::ServiceModule::ServiceInterface:setConfigured() must be " .
            " overriden or " .
            " EBox::Serice::Module::ServiceInterface::serviceModuleName must " .
            " return a valid gconf module");
    }

    return unless ($self->configured() xor $status);


    return $gconf->st_set_bool('_serviceConfigured', $status);
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

    my $gconf = $self->_gconfModule();
    unless (defined($gconf)) {
        throw EBox::Exceptions::Internal(
            "EBox::ServiceModule::ServiceInterface::isEnabled() must be " .
            " overriden or " .
            " EBox::Serice::Module::ServiceInterface::serviceModuleName must " .
            " return a valid gconf module");
    }

    if ($gconf->get_bool('_serviceModuleStatus') eq '') {
        return $self->defaultStatus();
    }

    return $gconf->get_bool('_serviceModuleStatus');
}

# Method: enableService 
#
#   Used to enable a service
#
# Paramters:
#
#   boolean - true to enable, false to disable 
sub enableService 
{
    my ($self, $status) = @_;

    my $gconf = $self->_gconfModule();
    unless (defined($gconf)) {
        throw EBox::Exceptions::Internal(
            "EBox::ServiceModule::ServiceInterface::enableService() must be " .
            " overriden or " .
            " EBox::Serice::Module::ServiceInterface::serviceModuleName must " .
            " return a valid gconf module");
    }

    EBox::debug("Module status: " . $self->isEnabled() . " new status: " .
    $status);
    return unless ($self->isEnabled() xor $status);

    $gconf->set_bool('_serviceModuleStatus', $status);
}

# Method: serviceModuleName
#
#   This method must be overriden if you want to automatically use the methods
#   isEnabled and enableService.
#
# Returns:
#
#   The name of a valid gconf module
sub serviceModuleName
{
    return undef;
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


sub _gconfModule
{
    my ($self) = @_;

    my $global = EBox::Global->instance();

    my $name = $self->serviceModuleName();
    return undef unless(defined($name) and $global->modExists($name));

    return $global->modInstance($name);
}

1;
