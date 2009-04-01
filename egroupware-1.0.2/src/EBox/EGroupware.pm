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


# Class: EBox::EGroupware
#
#   TODO: Documentation

package EBox::EGroupware;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::Model::ModelProvider
            EBox::Model::CompositeProvider EBox::LdapModule
            EBox::ServiceModule::ServiceInterface);


use Digest::MD5;

use EBox::Validate qw( :all );
use EBox::Global;
use EBox::Gettext;
use EBox::Sudo;
use EBox::EGroupwareLdapUser;

use EBox::Exceptions::InvalidData;
use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Exceptions::DataNotFound;

use constant PORT => 80;

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'egroupware',
            printableName => __('eGroupware'),
            domain => 'ebox-egroupware',
            @_);
}

## api functions

# Method: modelClasses
#
# Overrides:
#
#       <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
        'EBox::EGroupware::Model::VMailDomain',
        'EBox::EGroupware::Model::Applications',
        'EBox::EGroupware::Model::DefaultApplications',
        'EBox::EGroupware::Model::PermissionTemplates',
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
    return ['EBox::EGroupware::Composite::General'];
}


sub domain
{
    return 'ebox-egroupware';
}

# Method: actions
#
#   Override EBox::ServiceModule::ServiceInterface::actions
#
sub actions
{
    return [
    {
        'action' => __('Create PostgreSQL user egroupware'),
        'reason' => __('This user will be the owner of the egroupware database'),
        'module' => 'egroupware'
    },
    {
        'action' => __('Create PostgreSQL egroupware database'),
        'reason' => __('This database will store the data needed by eGroupware'),
        'module' => 'egroupware'
    }
    ];
}


# Method: usedFiles
#
#   Override EBox::ServiceModule::ServiceInterface::usedFiles
#
sub usedFiles
{
    my @usedFiles;

    push (@usedFiles, { 'file' => '/var/lib/egroupware/header.inc.php',
                        'module' => 'egroupware',
                        'reason' => __('To configure eGroupware access settings')
                      });

    push (@usedFiles, { 'file' => '/etc/postgresql/8.3/main/pg_hba.conf',
                        'module' => 'egroupware',
                        'reason' => __('To allow local access to egroupware database')
                      });

    push (@usedFiles, {
                        'file' => '/etc/ldap/slapd.conf',
                        'reason' => __('To add a new schema'),
                        'module' => 'users'
                      });

    return \@usedFiles;
}

# Method: enableActions
#
#   Override EBox::ServiceModule::ServiceInterface::enableActions
#
sub enableActions
{
    my ($self) = @_;

    # Generate password
    EBox::Sudo::root(EBox::Config::share() .
                    '/ebox-egroupware/ebox-init-egroupware init');

    # Write the generated password
    $self->_writeConfiguration();

    EBox::Sudo::root(EBox::Config::share() .
                     '/ebox-egroupware/ebox-egroupware-enable');

    # Migrate existing users
    EBox::Sudo::root(EBox::Config::share() .
                    '/ebox-egroupware/ebox-init-egroupware migrate');
}

# Method: serviceModuleName
#
#   Override EBox::ServiceModule::ServiceInterface::serviceModuleName
#
sub serviceModuleName
{
    return 'egroupware';
}

# Method: enableModDepends
#
#   Override EBox::ServiceModule::ServiceInterface::enableModDepends
#
sub enableModDepends
{
    return ['webserver', 'mail'];
}

# Method: isRunning
#
#   Override EBox::ServiceModule::ServiceInterface::isRunning
#
sub isRunning
{
#FIXME
#    return EBox::Service::running('ebox.egroupware');

    return (-f '/var/run/apache2.pid');
}

# Method: statusSummary
#
#       Show the event status summary
#
# Overrides:
#
#       <EBox::Module::statusSummary>
#
sub statusSummary
{
    my ($self) = @_;

    return new EBox::Summary::Status('egroupware', __('eGroupware'),
                                     $self->isRunning, $self->service);
}

# Method: service
#
#       Returns if the egroupware service is enabled
#
# Returns:
#
#       boolean - true if enabled, undef otherwise
#
sub service
{
    my ($self) = @_;

    return $self->isEnabled();
}


# Method: menu
#
#       Overrides EBox::Module method.
#
#
sub menu
{
    my ($self, $root) = @_;

    my $settings = new EBox::Menu::Item(
            'url' => 'EGroupware/Composite/General',
            'text' => __('eGroupware'));

    $root->add($settings);
}

# Comment out custom backups for now

# Method: makeBackup
#
#   Overrides EBox::Module::makeBackup
#
#sub makeBackup
#{
#    my ($self, $dir, %options) = @_;
#
#    $self->SUPER::makeBackup($dir, %options);
#
#    my $command = 'pg_dump egroupware';
#    EBox::Sudo::root("su postgres -c '$command' > $dir/egroupware.sql");
#}

# Method: restoreBackup
#
#   Overrides EBox::Module::restoreBackup
#
#sub restoreBackup
#{
#    my ($self, $dir, %options) = @_;
#
#    $self->SUPER::restoreBackup($dir, %options);
#
#    my $command = 'psql egroupware';
#    EBox::Sudo::root("su postgres -c '$command' < $dir/egroupware.sql");
#}


# Private functions

# Method: _regenConfig
#
#        Overrides EBox::Module::_regenConfig
#
sub _regenConfig
{
    my ($self) = @_;

    $self->_writeConfiguration();
    $self->_doDaemon();
}

# Method: _ldapModImplementation
#
sub _ldapModImplementation
{
    return new EBox::EGroupwareLdapUser();
}


# Method: _writeConfiguration
#
#       This method uses a mason template to generate and write the
#       configuration for /var/lib/egroupware/header.inc.php
#
sub _writeConfiguration
{
    my ($self) = @_;

    my $username = 'ebox';
    my $password = getPassword();
    my $md5pass = Digest::MD5::md5_hex($password);

    $self->writeConfFile('/var/lib/egroupware/header.inc.php',
                         '/egroupware/header.inc.php.mas',
                         [ header_passwd => $md5pass,
                           config_user => $username,
                           config_passwd => $md5pass,
                           db_pass => getPassword()]);

    $self->_configVDomain();
}

sub _configVDomain
{
    my ($self) = @_;

    my $model = $self->model('VMailDomain');
    my $vdomain = $model->vdomainValue();

    unless (defined($vdomain) and ($vdomain ne '_unset_')) {
        return;
    }

    EBox::Sudo::root(EBox::Config::share() . "/ebox-egroupware/ebox-egroupware-set-vdomain $vdomain");
}

sub _doDaemon
{
}

sub _stopService
{
}

# Method: getPassword
#
#       Returns the eGroupware admin password
#
# Returns:
#
#       string - password
#
# Exceptions:
#
#       Internal - If password can't be read
sub getPassword {

    my $path = EBox::Config->conf . "/ebox-egroupware.passwd";
    open(PASSWD, $path) or
        throw EBox::Exceptions::Internal("Could not open $path to " .
                "get egroupware password");

    my $pwd = <PASSWD>;
    close(PASSWD);

    $pwd =~ s/[\n\r]//g;

    return $pwd;
}

1;
