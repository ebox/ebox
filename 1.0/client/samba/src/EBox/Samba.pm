# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
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

package EBox::Samba;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::LdapModule EBox::FirewallObserver
            EBox::Report::DiskUsageProvider 
            EBox::ServiceModule::ServiceInterface
            EBox::Model::ModelProvider);


use EBox::Sudo qw( :all );
use EBox::Global;
use EBox::Ldap;
use EBox::Service;
use EBox::SambaLdapUser qw(PROFILESPATH);
use EBox::UsersAndGroups;
use EBox::Network;
use EBox::SambaFirewall;
use EBox::Dashboard::ModuleStatus;
use EBox::Dashboard::Widget;
use EBox::Dashboard::List;
use EBox::Menu::Item;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Exceptions::External;
use EBox::Gettext;
use EBox::Config;
use EBox::Model::ModelManager;


use File::Slurp qw(read_file write_file);
use Perl6::Junction qw(all any);
use Error qw(:try);

use constant SMBCONFFILE          => '/etc/samba/smb.conf';
use constant LIBNSSLDAPFILE       => '/etc/ldap.conf';
use constant SMBLDAPTOOLBINDFILE  => '/etc/smbldap-tools/smbldap_bind.conf';
use constant SMBLDAPTOOLBINDFILE_MASK => '0600';
use constant SMBLDAPTOOLBINDFILE_UID => '0';
use constant SMBLDAPTOOLBINDFILE_GID => '0';
use constant SMBLDAPTOOLCONFFILE  => '/etc/smbldap-tools/smbldap.conf';
use constant SMBPIDFILE           => '/var/run/samba/smbd.pid';
use constant NMBPIDFILE           => '/var/run/samba/nmbd.pid';
use constant MAXNETBIOSLENGTH     => 32;
use constant MAXWORKGROUPLENGTH   => 32;
use constant MAXDESCRIPTIONLENGTH => 255;
use constant SMBPORTS => qw(137 138 139 445);
use constant NMBDSERVICE => 'ebox.nmbd';
use constant SMBDSERVICE => 'ebox.smbd';

use constant FIX_SID_PROGRAM => '/usr/share/ebox-samba/ebox-fix-sid';
use constant QUOTA_PROGRAM => '/usr/share/ebox-samba/ebox-samba-quota';

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'samba', 
            printableName => __('file sharing'),
            domain => 'ebox-samba',
            @_);
    bless($self, $class);
    return $self;
}

sub domain
{
    return 'ebox-samba';
}

# Method: actions
#
# 	Override EBox::ServiceModule::ServiceInterface::actions
#
sub actions
{
    return [ 
    {
        'action' => __('Create Samba home directory for users and groups'),
        'reason' => __('eBox will create the home directories for Samba ' .
            'users and groups under /home/samba.'),
        'module' => 'samba'
    },
    {
        'action' => __('Add LDAP schemas'),
        'reason' => __('eBox will add two LDAP schemas: samba.schema and ' .
            'ebox.schema.'),
        'module' => 'samba'
    },
    {
        'action' => __('Set Samba LDAP admin dn password'),
        'reason' => __('eBox will configure Samba to use the LDAP admin dn ' .
            'password.'),
        'module' => 'samba'
    },
    {
        'action' => __('Set Samba LDAP admin dn password'),
        'reason' => __('eBox will configure Samba to use the LDAP admin dn ' .
            'password.'),
        'module' => 'samba'
    },
    ];
}

# Method: usedFiles 
#
#   Override EBox::ServiceModule::ServiceInterface::files
#
sub usedFiles 
{
    return [
    {
        'file' => '/etc/samba/smb.conf',
            'reason' => __('To set up Samba according to your configuration'),
        'module' => 'samba'
    },
    {
        'file' => '/etc/smbldap-tools/smbldap.conf',
        'reason' => __('To set up smbldap-tools according to your' .
            ' configuration'),
        'module' => 'samba'
    },
    {
        'file' => '/etc/smbldap-tools/smbldap_bind.conf',
        'reason' => __('To set up smbldap-tools according to your LDAP' .
            ' configuration'),
        'module' => 'samba'
    },
    {
        'file' => '/etc/ldap/slapd.conf',
        'reason' => __('To add two new schemas and the set ACLs'),
        'module' => 'users'
    },
    {
        'file' => '/etc/nsswitch.conf',
        'reason' => __('To make NSS use LDAP resolution for user and group '.
            'accounts. Needed for Samba PDC configuration.'),
        'module' => 'samba'
    },
    {
        'file' => '/etc/ldap.conf',
        'reason' => __('To let NSS know how to access LDAP accounts'),
        'module' => 'samba'
    },
    {
        'file' => '/etc/ldap.secret',
        'reason' => __('To copy LDAP admin password generated by eBox and '.
             'allow NSS to access LDAP'),
        'module' => 'samba'
    },
    {
        'file' => '/etc/fstab',
        'reason' => __('To add quota support to /home partition'),
        'module' => 'samba'
    }
    ];
}

# Method: enableActions 
#
#   Override EBox::ServiceModule::ServiceInterface::enableActions
#
sub enableActions
{
    root(EBox::Config::share() . '/ebox-samba/ebox-samba-enable');
}

#  Method: serviceModuleName
#
#   Override EBox::ServiceModule::ServiceInterface::servivceModuleName
#
sub serviceModuleName
{
    return 'samba';
}

#  Method: enableModDepends
#
#   Override EBox::ServiceModule::ServiceInterface::enableModDepends
#
sub enableModDepends 
{
    return ['network', 'users'];
}


# Method: models
#
# Overrides:
#
#       <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{

    my ($self) = @_;

    return  [
               'EBox::Samba::Model::SambaShares',
               'EBox::Samba::Model::SambaSharePermissions',
               'EBox::Samba::Model::DeletedSambaShares',
           ];

}

#
# Method: shares
#
#   It returns the custom shares added by the user.
#
# Returns:
#
#   Array ref containing hash ref with:
#
#   share   - share's name
#   path    - share's path
#   comment - share's comment
#   readOnly - string containing users and groups with read-only permissions
#   readWrite - string containing users and groups with read and write 
#               permissions
#   administrators  - string containing users and groups with admin priviliges
#                   on the share
#   validUsers - readOnly + readWrite + administrators
sub shares
{
    my ($self) = @_;
    my $shares = $self->model('SambaShares');
    my @shares;

    for my $row (@{$shares->rows()}) {
        my @readOnly;
        my @readWrite;
        my @administrators;
        my $shareConf;

        $shareConf->{'share'} = $row->elementByName('share')->value();
        $shareConf->{'comment'} = $row->elementByName('comment')->value(); 

        my $path = $row->elementByName('path');

        if ($path->selectedType() eq 'ebox') {
            $shareConf->{'path'} = '/home/samba/shares/';
        }
        $shareConf->{'path'} .= $path->value();

        for my $subRow (@{$row->subModel('access')->rows()}) {
            my $userType = $subRow->elementByName('user_group');
            my $preCar = '';
            if ($userType->selectedType() eq 'group') {
                $preCar = '@';
            }
            my $user =  $preCar . '"' . $userType->printableValue() . '"';

            my $permissions = $subRow->elementByName('permissions');

            if ($permissions->value() eq 'readOnly') {
                push (@readOnly, $user);
            } elsif ($permissions->value() eq 'readWrite') {
                push (@readWrite, $user);
            } elsif ($permissions->value() eq 'administrator') {
                push (@administrators, $user)
            }
        }

        next unless (@readOnly or @readWrite or @administrators);

        $shareConf->{'readOnly'} = join (', ', @readOnly);
        $shareConf->{'readWrite'} = join (', ', @readWrite);
        $shareConf->{'administrators'} = join (', ', @administrators);
        $shareConf->{'validUsers'} = join (', ', @readOnly, 
                                                 @readWrite,
                                                 @administrators);

        push (@shares, $shareConf);
    }

    return \@shares;
}


sub _exposedMethods
{
    return {
            'getPathByShareName' => {
            'action' => 'get',
                'path' => [ 'SambaShares'],
                'indexes' => [ 'share'],
                'selector' => [ 'path']
            },
            'getUserByIndex' => {
                'action' => 'get',
                'path' => [ 'SambaShares',
                'access'
                    ],
                'indexes' => ['share', 'id'],
                'selector' => ['user_group']
            },
            'getPermissionsByIndex' => {	
                'action' => 'get',
                'path' => [ 'SambaShares',
                'access'
                    ],
                'indexes' => ['share', 'id'],
                'selector' => ['permissions']
            }
    };
}

# return interface upon samba should listen as a comma-separated string
# XXX this is a quick fix for this version. See #529
sub _interfacesToListenOn
{
    my ($self) = @_;
    my $interfaces;

    my $global = EBox::Global->getInstance();

    my $net = $global->modInstance('network');
    my $internalIfaces = $net->InternalIfaces;

    my @moduleGeneratedIfaces = ();

    # XXX temporal  fix until #529 is fixed
    if ($global->modExists('openvpn')) {
        my $openvpn = $global->modInstance('openvpn');
        my @openvpnDaemons = $openvpn->activeDaemons();
        my @openvpnIfaces  = map { $_->iface() }  @openvpnDaemons;

        push @moduleGeneratedIfaces, @openvpnIfaces;
    }


    $interfaces = join (',', @{$internalIfaces}, @moduleGeneratedIfaces, 'lo');
    return $interfaces;
}

sub _setSambaConf
{
    my $self = shift;

    my $net = EBox::Global->modInstance('network');
    my $interfaces = $self->_interfacesToListenOn();

    my $ldap = EBox::Ldap->instance();
    my $smbimpl = new EBox::SambaLdapUser;

    $smbimpl->setSambaDomainName($self->workgroup) ;
    $smbimpl->updateNetbiosName($self->netbios);
    $smbimpl->updateSIDEntries();

    my $ldapconf = $ldap->ldapConf();
    $ldapconf->{'users'} = EBox::UsersAndGroups::USERSDN;
    $ldapconf->{'groups'} = EBox::UsersAndGroups::GROUPSDN;

    my @array = ();
    push(@array, 'netbios'   => $self->netbios);
    push(@array, 'desc'      => $self->description);
    push(@array, 'workgroup' => $self->workgroup);
    push(@array, 'ldap'      => $ldapconf);
    push(@array, 'dirgroup'  => $smbimpl->groupShareDirectories);
    push(@array, 'ifaces'    => $interfaces); 
    push(@array, 'printers'  => $self->_sambaPrinterConf());
    push(@array, 'active_file' => $self->fileService());
    push(@array, 'active_printer' => $self->printerService());
    push(@array, 'pdc' => $self->pdc());
    push(@array, 'roaming' => $self->roamingProfiles());
    push(@array, 'backup_path' => EBox::Config::conf() . '/backups');
    push(@array, 'shares' => $self->shares());

    $self->writeConfFile(SMBCONFFILE, "samba/smb.conf.mas", \@array);

    root(EBox::Config::share() . '/ebox-samba/ebox-setadmin-pass');

    my $users = EBox::Global->modInstance('users');

    @array = ();
    push(@array, 'basedc'    => $ldapconf->{'dn'});
    push(@array, 'ldapi'     => $ldapconf->{'ldapi'});
    push(@array, 'binddn'     => $ldapconf->{'rootdn'});
    push(@array, 'bindpw'    => $ldap->getPassword());
    push(@array, 'usersdn'   => $users->usersDn);
    push(@array, 'groupsdn'  => $users->groupsDn); 
    push(@array, 'computersdn' => 'ou=Computers,' . $ldapconf->{'dn'});

    $self->writeConfFile(LIBNSSLDAPFILE, "samba/ldap.conf.mas", 
            \@array);

    $self->setSambaLdapToolsConf();


    # Set SIDs using the net tool this is neccesary bz if we change the
    #  domain name we can lost the domain SID
    my $sid = $self->_sidFromLdap();
    defined $sid or $sid = $smbimpl->alwaysGetSID();
    $self->setNetSID($sid);

    # Remove shares
    $self->model('DeletedSambaShares')->removeDirs();
    # Create samba shares
    $self->model('SambaShares')->createDirs();

}


sub setSambaLdapToolsConf
{
    my ($self, %params) = @_;

    my $ldap = EBox::Ldap->instance();

    my $netbios = exists $params{netbios} ? $params{netbios} : $self->netbios;
    my $domain = exists $params{domain} ? $params{domain} : $self->workgroup;
    my $sid;
    if (exists $params{sid}) {
        $sid = $params{sid};
    }
    else {
        my $sambaLdap = new EBox::SambaLdapUser;
        $sid = $sambaLdap->getSID();
    }

    my @array = ();
    push(@array, 'netbios'  => $netbios);
    push(@array, 'domain'   => $domain);
    push(@array, 'sid' 	=> $sid);
    push(@array, 'ldap'     => $ldap->ldapConf());

    $self->writeConfFile(SMBLDAPTOOLCONFFILE, "samba/smbldap.conf.mas", 
            \@array);

    @array = ();
    push(@array, 'pwd' 	=> $ldap->getPassword());
    push(@array, 'ldap'     => $ldap->ldapConf());

    $self->writeConfFile(SMBLDAPTOOLBINDFILE,
            "samba/smbldap_bind.conf.mas", \@array, 
            { mode => SMBLDAPTOOLBINDFILE_MASK, 
            uid => SMBLDAPTOOLBINDFILE_UID, 
            gid => SMBLDAPTOOLBINDFILE_GID });
}

sub _shareUsers {
    my $state = 0;

    my $pids = {};

    use File::Slurp;
    for my $line (`smbstatus`) {
        chomp($line);
        if($state == 0) {
            if($line =~ '----------------------------') {
                $state = 1;
            }
        } elsif($state == 1) {
            if($line eq '') {
                $state = 2;
            } else {
                # 1735  javi   javi     blackops  (192.168.45.48)
                $line =~ m/(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+\((\S+)\)/;
                my ($pid, $user, $machine) = ($1, $2, $4);
                $pids->{$pid} = { 'user' => $user, 'machine' => $machine };
            }
        } elsif($state == 2) {
            if($line =~ '----------------------------') {
                $state = 3;
            }
        } elsif($state == 3) {
            if($line eq '') {
                last;
            } else {
            #administracion   1735   blackops      Wed Nov 26 17:27:19 2008
                $line =~ m/(\S+)\s+(\d+)\s+(\S+)\s+(\S.+)/;
                my($share, $pid, $date) = ($1, $2, $4);
                $pids->{$pid}->{'share'} = $share;
                $pids->{$pid}->{'date'} = $date;
            }
        }
    }
    return [values %{$pids}];
}

sub _sharesGroupedBy
{
    my ($group) = @_;

    my $shareUsers = _shareUsers();

    my $groupedInfo = {};
    for my $info (@{$shareUsers}) {
        if(!defined($groupedInfo->{$info->{$group}})) {
            $groupedInfo->{$info->{$group}} = [];
        }
        push(@{$groupedInfo->{$info->{$group}}}, $info);
    }
    return $groupedInfo;
}

sub sharesByUserWidget
{
    my ($self, $widget) = @_;

    my $sharesByUser = _sharesGroupedBy('user');

    for my $user (sort keys %{$sharesByUser}) {
        my $section = new EBox::Dashboard::Section($user, $user);
        $widget->add($section);
        my $titles = [__('Share'), __('Source machine'), __('Connected since')];

        my $rows = {};
        foreach my $share (@{$sharesByUser->{$user}}) {
            my $id = $share->{'share'} . '_' . $share->{'machine'};
            $rows->{$id} = [$share->{'share'}, $share->{'machine'}, $share->{'date'}];
        }
        my $ids = [sort keys %{$rows}];
        $section->add(new EBox::Dashboard::List(undef, $titles, $ids, $rows));
    }
}

sub usersByShareWidget
{
    my ($self, $widget) = @_;

    my $usersByShare = _sharesGroupedBy('share');

    for my $share (sort keys %{$usersByShare}) {
        my $section = new EBox::Dashboard::Section($share, $share);
        $widget->add($section);
        my $titles = [__('User'), __('Source machine'), __('Connected since')];

        my $rows = {};
        foreach my $user (@{$usersByShare->{$share}}) {
            my $id = $user->{'user'} . '_' . $user->{'machine'};
            $rows->{$id} = [$user->{'user'}, $user->{'machine'}, $user->{'date'}];
        }
        my $ids = [sort keys %{$rows}];
        $section->add(new EBox::Dashboard::List(undef, $titles, $ids, $rows));
    }
}

# Method: widgets
#
#	Override EBox::Module::widgets
#
sub widgets
{
    return {
        'sharesbyuser' => {
            'title' => __("Shares by user"),
                'widget' => \&sharesByUserWidget,
                'default' => 1
        },
        'usersbyshare' => {
            'title' => __("Users by share"),
                'widget' => \&usersByShareWidget,
                'default' => 1
        }
    };
}

# Method: _daemons
#
# 	Override EBox::ServiceModule::ServiceInterface::_daemons
#
sub _daemons
{
    return [
        {
            'name' => SMBDSERVICE
        },
        {
            'name' => NMBDSERVICE
        }
    ];
}

sub _regenConfig
{
    my ($self) = @_;

    $self->_stopService();
    $self->_setSambaConf();
    $self->_enforceServiceState();
}

# Function: usesPort
#
#       Implements EBox::FirewallObserver interface
#
sub usesPort # (protocol, port, iface)
{
    my ($self, $protocol, $port, $iface) = @_;

    return undef unless($self->isEnabled());

    foreach my $smbport (SMBPORTS) {
        return 1 if ($port eq $smbport);
    }

    return undef;
}

sub firewallHelper
{
    my $self = shift;
    if ($self->isEnabled()) {
        return new EBox::SambaFirewall();
    }
    return undef;
}

sub menu
{
    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder('name' => 'File sharing',
            'text' => __('File sharing'));

    $folder->add(new EBox::Menu::Item('url' => 'Samba/Index',
                'text' => __('General settings')));

    $folder->add(new EBox::Menu::Item('url' => 'Samba/View/SambaShares',
                'text' => __('Shares')));

    $root->add($folder);
}

#   Function: setFileService 
#
#       Sets the file sharing service through samba
#
#   Parameters:
#
#       enabled - boolean. True enable, undef disable
#
sub setFileService # (enabled) 
{
    my ($self, $active) = @_;
    ($active and $self->fileService) and return;
    (!$active and !$self->fileService) and return;

    $self->enableService($active);
}

#   Function: fileService
#
#       Returns if the file sharing service is enabled  
#
#   Returns:
#
#       boolean - true if enabled, otherwise undef      
#
sub fileService
{
    my $self = shift;

    return $self->isEnabled();
}


#   Function: setPrinterService 
#
#       Sets the printer sharing service through samba and cups
#
#   Parameters:
#
#       enabled - boolean. True enable, undef disable
#
sub setPrinterService # (enabled) 
{
    my ($self, $active) = @_;
    ($active and $self->printerService) and return;
    (!$active and !$self->printerService) and return;

#	if ($active) {
#		if (not $self->fileService) {
#			my $fw = EBox::Global->modInstance('firewall');
#			foreach my $smbport (SMBPORTS) {
#				unless ($fw->availablePort('tcp',$smbport) and
#					$fw->availablePort('udp',$smbport)) {
#					throw EBox::Exceptions::DataExists(
#					'data'  => __('listening port'),
#					'value' => $smbport);
#				}
#			}
#		}
#	}
    $self->set_bool('printer_active', $active);
}

#   Method: servicePrinter
#
#       Returns if the printer sharing service is enabled  
#
#   Returns:
#
#       boolean - true if enabled, otherwise undef      
#
sub printerService 
{
    my $self = shift;
    return $self->get_bool('printer_active');
}

#   Method: pdc
#
#       Returns if samba must configured as a PDC 
#
#   Returns:
#
#       boolean - true if enabled, otherwise undef      
#
sub pdc
{
    my ($self) = @_;
    return $self->get_bool('pdc');
}

#   Method: setPdc
#
#      	Set the configuration for samba, PDC or file server
#
#   Parameters:
#
#       enable - true if enabled, otherwise undef      
#
sub  setPdc
{
    my ($self, $enable) = @_;

    ($self->pdc eq $enable) and return;
    $self->set_bool('pdc', $enable);
}
#   Method: adminUser
#
#	Check if a given user is a Domain Administrator
#
#   Parameters:
#
#       user - string containign the username
#
#  Returns:
#
#  	bool - true if it is, otherwise undef
#
sub  adminUser
{
    my ($self, $user) = @_;
    ($user) or return;
    my $usermod = EBox::Global->modInstance('users');


    my $isDomainAdmin  = $user eq any @{$usermod->usersInGroup('Domain Admins') };
    my $isAdministrator = $user eq any @{$usermod->usersInGroup('Administrators') };

    if ($isDomainAdmin and $isAdministrator) {
        return 1;
    }
    elsif ((not $isDomainAdmin) and (not $isAdministrator)) {
        return undef;
    }
    else {
        EBox::error("The user has incomplete group memberships; to be administrator he must be both member of domain Admins and Administrators group");                                                        
        return undef; 
    }
}


#   Method: setAdminUser
#
#	Add a given user to the Domain Admins group
#
#   Parameters:
#
#       user - string containign the username
#	admin -  true if it must be an administrator, undef otherwise
#
#
sub  setAdminUser 
{
    my ($self, $user, $admin) = @_;
    ($user) or return;
    ($admin xor $self->adminUser($user)) or return;
    my $usermod = EBox::Global->modInstance('users');
    if ($admin) {
        $usermod->addUserToGroup($user, 'Domain Admins');
        $usermod->addUserToGroup($user, 'Administrators');
    } else {
        $usermod->delUserFromGroup($user, 'Domain Admins');
        $usermod->delUserFromGroup($user, 'Administrators');
    }
}

sub setNetbios # (enabled) 
{
    my ($self, $netbios) = @_;
    unless (_checkNetbiosName($netbios)) {
        throw EBox::Exceptions::InvalidData
            ('data' => __('netbios'), 'value' => $netbios);
    }
    ($netbios eq $self->netbios) and return;
    $self->set_string('netbios', $netbios);
}

#returns netbios name
sub netbios
{
    my $self = shift;
    return $self->get_string('netbios');
}

sub setDescription # (enabled) 
{
    my ($self, $description) = @_;
    unless (_checkDescriptionName($description)) {
        throw EBox::Exceptions::InvalidData
            ('data' => __('description'), 'value' => $description);
    }
    ($description eq $self->description) and return;
    $self->set_string('description', $description);
}

sub roamingProfiles
{
    my ($self) = @_;
    return $self->get_bool('roaming');
}

sub setRoamingProfiles # (enabled) 
{
    my ($self, $enable) = @_;
    return unless ($self->roamingProfiles() xor $enable);
    $self->set_bool('roaming', $enable);
}

#returns description name
sub description
{
    my $self = shift;
    return $self->get_string('description');
}

sub setWorkgroup # (enabled) 
{
    my ($self, $workgroup) = @_;
    unless (_checkWorkgroupName($workgroup)) {
        throw EBox::Exceptions::InvalidData
            ('data' => __('working group'), 'value' => $workgroup);
    }
    ($workgroup eq $self->workgroup) and return;
    $self->set_string('workgroup', $workgroup);
}

#returns workgroup name
sub workgroup
{
    my $self = shift;
    return $self->get_string('workgroup');
}

sub setDefaultUserQuota # (enabled) 
{
    my ($self, $userQuota) = @_;
    unless (_checkQuota($userQuota)) {
        throw EBox::Exceptions::InvalidData
            ('data' => __('quota'), 'value' => $userQuota);
    }
    ($userQuota eq $self->defaultUserQuota) and return;
    $self->set_int('userquota', $userQuota);
}

#returns userQuota name
sub defaultUserQuota
{
    my $self = shift;
    return $self->get_int('userquota');
}

# LdapModule implmentation    
sub _ldapModImplementation    
{
    my $self;

    return new EBox::SambaLdapUser();
}

# Helper functions
sub _checkNetbiosName ($)
{
    my $name = shift;
    (length($name) <= MAXNETBIOSLENGTH) or return undef;
    (length($name) > 0) or return undef;
    return 1;
}

sub _checkWorkgroupName ($)
{
    my $name = shift;
    (length($name) <= MAXWORKGROUPLENGTH) or return undef;
    (length($name) > 0) or return undef;
    return 1;
}

sub _checkDescriptionName ($)
{
    my $name = shift;
    (length($name) <= MAXDESCRIPTIONLENGTH) or return undef;
    (length($name) > 0) or return undef;
    return 1;
}

sub _checkQuota ($)
{
    my $quota = shift;
    ($quota =~ /\D/) and return undef;
    return 1;
}	

sub addPrinter # (resource)
{
    my $self = shift;
    my $name = shift;

    return if ($self->dir_exists("printers/$name"));
    $self->set_list("printers/$name/users", "string", []);
    $self->set_list("printers/$name/groups", "string", []);
    $self->set_bool("printers/external", undef);

}

sub _addExternalPrinter
{
    my ($self, $name) = @_;
    $self->set_list("printers/$name/users", "string", []);
    $self->set_list("printers/$name/groups", "string", []);
    $self->set_bool("printers/$name/external", 1);
}

sub printers 
{
    my $self = shift;

    my $global = EBox::Global->getInstance();
    my %external;
    if ($global->modExists('printers')) {
        my $printers = $global->modInstance('printers');
        %external = map { $_ => 1 } @{$printers->fetchExternalCUPSPrinters()};
    } else {
        return [];
    }

    my @printers;
    my $readOnly = $self->isReadOnly();
    for my $printer (@{$self->array_from_dir("printers")}) {
        my $name = $printer->{_dir};
        my $key = "printers/$name/external";
        my $isExt = $self->get_bool($key);
        if ($isExt and not exists $external{$name}) {
            $self->delPrinter($name) unless ($readOnly);
            $external{$name} = 'removed';
        }  elsif ($isExt) {
            $external{$name} = 'exists';
        }
        push (@printers,  $printer->{'_dir'});
    }

    unless ($readOnly) {
        for my $newPrinter (grep { $external{$_} == 1  } keys %external) {
            $self->_addExternalPrinter($newPrinter);
            push (@printers, $newPrinter);
        }
    }

    return [sort @printers];
}

sub _addUsersToPrinter # (printer, users)
{
    my $self = shift;
    my $printer = shift;
    my $users = shift;

    unless ($self->dir_exists("printers/$printer")) {
        throw EBox::Exceptions::DataNotFound('data' => 'printer',
                'value' => $printer);
    }


    for my $username (@{$users}) {
        _checkUserExists($username);
    }


    $self->set_list("printers/$printer/users", "string", $users);
}

sub _addGroupsToPrinter # (printer, groups)
{
    my $self = shift;
    my $printer = shift;
    my $groups = shift;

    unless ($self->dir_exists("printers/$printer")) {
        throw EBox::Exceptions::DataNotFound('data' => 'printer',
                'value' => $printer);
    }


    for my $groupname (@{$groups}) {
        _checkGroupExists($groupname);
    }

    $self->set_list("printers/$printer/groups", "string", $groups);
}

sub _printerUsers # (printer)
{
    my $self = shift;
    my $printer = shift;

    unless ($self->dir_exists("printers/$printer")) {
        throw EBox::Exceptions::DataNotFound('data' => 'printer',
                'value' => $printer);
    }

    return $self->get_list("printers/$printer/users");
}

sub _printerGroups # (group)
{
    my $self = shift;
    my $printer = shift;

    unless ($self->dir_exists("printers/$printer")) {
        throw EBox::Exceptions::DataNotFound('data' => 'printer',
                'value' => $printer);
    }

    return $self->get_list("printers/$printer/groups");
}

sub _printersForUser # (user)
{
    my $self = shift;
    my $user = shift;

    _checkUserExists($user);

    my @printers;
    for my $name (@{$self->printers()}) {
        my $print = { 	'name' => $name, 'allowed' => undef };
        my $users = $self->get_list("printers/$name/users");
        if (@{$users}) {
            $print->{'allowed'} = 1 if (grep(/^$user$/, @{$users}));
        }
        push (@printers, $print);
    }

    return \@printers;
}

sub _printersForGroup # (user)
{
    my $self = shift;
    my $group = shift;

    _checkGroupExists($group);

    my @printers;
    for my $printer (@{$self->array_from_dir("printers")}) {
        my $name = $printer->{'_dir'};
        my $print = { 'name' => $name, 'allowed' => undef };
        my $groups = $self->get_list("printers/$name/groups");
        if (@{$groups}) {
            $print->{'allowed'} = 1 if (grep(/^$group$/, @{$groups}));
        }
        push (@printers, $print);
    }

    return \@printers;
}

sub setPrintersForUser # (user, printers)
{
    my $self = shift;
    my $user = shift;
    my $newconf = shift;

    _checkUserExists($user);

    my %currconf;
    for my $conf (@{$self->_printersForUser($user)}) {
        $currconf{$conf->{'name'}} = $conf->{'allowed'};
    }
    my @changes;
    for my $conf (@{$newconf}) {
        if ($currconf{$conf->{'name'}} xor $conf->{'allowed'}) {
            push (@changes, $conf);
        }
    }

    for my $printer (@changes) {
        my @users;
        my $new = undef;
        my $name = $printer->{'name'};
        if ($printer->{'allowed'}) {
            @users = @{$self->_printerUsers($name)};
            next if (grep(/^$user$/, @users));
            push (@users, $user);
            $new = 1;
        } else {
            my @ousers = @{$self->_printerUsers($name)};
            @users = grep (!/^$user$/, @ousers);
            if (@users != @ousers) {
                $new = 1;
            }
        }

        $self->_addUsersToPrinter($name, \@users) if ($new);
    }
}

sub setPrintersForGroup # (user, printers)
{
    my $self = shift;
    my $group = shift;
    my $newconf = shift;

    _checkGroupExists($group);

    my %currconf;
    for my $conf (@{$self->_printersForGroup($group)}) {
        $currconf{$conf->{'name'}} = $conf->{'allowed'};
    } 
    my @changes;
    for my $conf (@{$newconf}) {
        if ($currconf{$conf->{'name'}} xor $conf->{'allowed'}) {
            push (@changes, $conf);
        }
    }

    for my $printer (@changes) {
        my @groups;
        my $new = undef;
        my $name = $printer->{'name'};
        if ($printer->{'allowed'}) {
            @groups = @{$self->_printerGroups($name)};
            next if (grep(/^$group$/, @groups));
            push (@groups, $group);
            $new = 1;
        } else {
            my @ogroups = @{$self->_printerGroups($name)};
            @groups = grep (!/^$group$/, @ogroups);
            if (@groups != @ogroups) {
                $new = 1;
            }
        }

        $self->_addGroupsToPrinter($name, \@groups) if ($new);
    }
}


sub delPrinter # (resource)
{
    my $self = shift;
    my $name = shift;

    unless ($self->dir_exists("printers/$name")) {
        throw EBox::Exceptions::DataNotFound('data' => 'printer',
                'value' => $name);
    }

    $self->delete_dir("printers/$name");
}

sub existsShareResource # (resource)
{
    my $self = shift;
    my $name = shift;

    my $usermod = EBox::Global->modInstance('users');
    if ($usermod->userExists($name)) {
        return __('user');
    }
    if ($usermod->groupExists($name)) {
        return __('group');
    }
    for my $printer (@{$self->printers()}) {
        return __('printer') if ($name eq $printer);
    }

    return undef;
}

sub _checkUserExists # (user)
{
    my $user = shift;

    my $usermod = EBox::Global->modInstance('users');
    unless ($usermod->userExists($user)){
        throw EBox::Exceptions::DataNotFound(
                'data'  => __('user'),
                'value' => $user);
    }

    return 1;
}

sub _checkGroupExists # (user)
{
    my $group = shift;

    my $groupmod = EBox::Global->modInstance('users');
    unless ($groupmod->groupExists($group)){
        throw EBox::Exceptions::DataNotFound(
                'data'  => __('group'),
                'value' => $group);
    }

    return 1;
}

sub _sambaPrinterConf 
{
    my $self = shift;

    my @printers;
    foreach my $printer (@{$self->printers()}) {
        my $users = "";
        for my $user (@{$self->_printerUsers($printer)}) {
            $users .= "\"$user\" ";
        }
        for my $group (@{$self->_printerGroups($printer)}) {
            $users .= "\@\"$group\" ";
        }
        push (@printers, { 'name' => $printer , 'users' => $users});
    }

    return \@printers;
}

sub enableQuota
{
    return (EBox::Config::configkey('enable_quota') eq 'yes');
}

# Method: currentUserQuota
#
# 	Fetch the current set quota for a given user
#
# Parameters:
#	
#	user - string
#
# Returns:
#
#	Integer - quota in MB. 0 means no quota
#
sub currentUserQuota
{
    my ($self, $user) = @_;

    my $usermod = EBox::Global->modInstance('users');
    unless (defined($user) and $usermod->uidExists($user)) {
        throw EBox::Exceptions::External("user is not valid");
    }
    my @quotaValues = @{root(QUOTA_PROGRAM . " -q $user ")};

    return $quotaValues[0];
}

# Method: setUserQuota
#
# 	Set user quota	
#
# Parameters:
#
# 	Quota - Integer. Quota in MB. 0 no quota.
#
# Returns:
#
#	Integer - quota in MB. 0 means no quota
#
sub setUserQuota 
{
    my ($self, $user, $userQuota) = @_;

    return unless ($self->enableQuota());

    my $usermod = EBox::Global->modInstance('users');
    unless (defined($user) and $usermod->uidExists($user)) {
        throw EBox::Exceptions::External("user is not valid");
    }

    unless (_checkQuota($userQuota)) {
        throw EBox::Exceptions::InvalidData
            ('data' => __('quota'), 'value' => $userQuota);
    }

    my $quota = $userQuota * 1024;

    root(QUOTA_PROGRAM . " -s $user $quota");
}

sub extendedBackup
{
    my ($self, %options) = @_;
    my $dir     = $options{dir};

    $self->_dumpSharesFiles($dir);
}

sub extendedRestore
{
    my ($self, %options) = @_;
    my $dir     = $options{dir};

    $self->_loadSharesFiles($dir);
}

sub dumpConfig
{
    my ($self, $dir) = @_;

    $self->_dumpSharesTree($dir);
    $self->_dumpProfiles($dir);
}

sub restoreConfig
{
    my ($self, $dir) = @_;

    $self->_loadSharesTree($dir);  $self->_loadProfiles($dir);
    $self->_fixLeftoverSharedDirectories();
    $self->fixSIDs();

    my $sambaLdapUser = new EBox::SambaLdapUser;
    $sambaLdapUser->migrateUsers();
}

sub restoreDependencies
{
    my ($self) = @_;
    return ['users'];
}


sub _dumpSharesTree
{
    my ($self, $dir) = @_;

    my $sambaLdapUser = new EBox::SambaLdapUser;
    my @shares = map {
        my $share = $_;
        my ($uid, $gid, $permissions);
        if (defined $share) {
            my $stat = EBox::Sudo::stat($share);
            if (defined $stat) {
                $permissions = EBox::FileSystem::permissionsFromStat($stat) ;
                $uid = $stat->uid;
                $gid = $stat->gid;
            }
            else {
                EBox::warn("Cannot stat directory $share. This directory will be ignored");
            }
        }
        (defined $share) and (defined $permissions) ? "$share:$uid:$gid:$permissions" : ();
    } @{ $sambaLdapUser->sharedDirectories() };


    my $sharesTreeData = join "\n",  @shares;
    write_file($self->_sharesTreeFile($dir), $sharesTreeData);
}

sub _loadSharesTree
{
    my ($self, $dir) = @_;

    my $contents = read_file($self->_sharesTreeFile($dir));

    my @shares = split "\n", $contents; 

    if (not @shares) {
        # maybe the file is in the old format. It will have problems with spaces
        # in directory names
        @shares = split '\s+', $contents;
    } 


    foreach my $dirInfo (@shares) {
        my ($dir, $uid, $gid, $perm) = split ':', $dirInfo;

        if (!-d $dir) {
            EBox::Sudo::root("/bin/mkdir -p  '$dir'");
        }

        EBox::Sudo::root("/bin/chmod $perm '$dir'"); # restore permissions
        EBox::Sudo::root("/bin/chown $uid.$gid '$dir'");

    } 
}


sub _dumpProfiles
{
    my ($self, $dir) = @_;
    my $archive = $self->_profilesArchive($dir);

    (-d PROFILESPATH) or return;

    my $tarCommand = "/bin/tar -cf $archive --bzip2 --atime-preserve --absolute-names --preserve --same-owner " . PROFILESPATH;
    EBox::Sudo::root($tarCommand);
}


sub _loadProfiles
{
    my ($self, $dir) = @_;
    my $archive = $self->_profilesArchive($dir);

    (-e $archive) or
        return;

    my $tarCommand = "/bin/tar -xf $archive --bzip2 --atime-preserve --absolute-names --preserve --same-owner";
    EBox::Sudo::root($tarCommand);
}


sub _profilesArchive
{
    my ($self, $dir) = @_;
    return "$dir/profiles.tgz";
}

sub fixSIDs
{
    my ($self)  = @_;

    # we use  the SID of the 'Domain Admins' standard group to extract the domain
    # SID portion
    my $sambaLdapUser   = new EBox::SambaLdapUser;

    my $domainSid = _sidFromLdap();

    if (not $sambaLdapUser->checkDomainSID($domainSid)) {
    # for first time..
    # XXX this must be more elegant!
    #    print "NOT DEFINED\n";
        $domainSid = $sambaLdapUser->alwaysGetSID;
    }


    #  print "DSID $domainSid\n";

    my $cmd = FIX_SID_PROGRAM . ' ' . $domainSid;
    EBox::Sudo::root($cmd);
}

# get the sid from a ldap entry (currrently it uses the Domain Admins SID's
# group bz it not garanteed the sambaDomain object exists)
sub _sidFromLdap
{
    my ($self) = @_;

    my $sambaLdapUser   = new EBox::SambaLdapUser;
    my $domainSid;

    try {
        my $domainAdminsSid = $sambaLdapUser->getGroupSID('Domain Admins');
#   print "domainAdminsSid $domainAdminsSid\n";
        if ($domainAdminsSid) {
            $domainSid = $domainAdminsSid;
            $domainSid =~ s/-\d+?$//;
        }

    }
    otherwise {
        $domainSid = undef;
    };

    return $domainSid;
}


# sets the sID using the net tool
sub setNetSID
{
    my ($self, $sid) = @_;

    $self->_setNetDomainSID($sid);
    $self->_setNetLocalSID($sid);
}

sub _setNetLocalSID
{
    my ($self, $domainSID) = @_;
    my $cmd = "net  SETLOCALSID $domainSID";
    EBox::Sudo::root($cmd);
}


sub _setNetDomainSID
{
    my ($self, $domainSID) = @_;
    my $cmd = "net  SETDOMAINSID $domainSID";
    EBox::Sudo::root($cmd);
}



sub _sharesTreeFile
{
    my ($self, $dir) = @_;
    return "$dir/sharesTree.bak";
} 

sub  _dumpSharesFiles
{
    my ($self, $dir) = @_;

    my $sambaLdapUser = new EBox::SambaLdapUser;
    my @dirs;
    foreach my $share (@{ $sambaLdapUser->sharedDirectories()}) {
        next if grep { EBox::FileSystem::isSubdir($share, $_) } @dirs; # ignore if is a subdir of a directory already in the list
            @dirs = grep { !EBox::FileSystem::isSubdir($_, $share)  } @dirs; # remove subdirectories of share from the list
            push @dirs, $share;
    }

    # escape directories
    @dirs = map {  "'$_'" } @dirs;

    if (@dirs > 0) {
        my $tarFile = $self->_sharesFilesArchive($dir);

        my $tarCommand = "/bin/tar -cf $tarFile --bzip2 --atime-preserve --absolute-names --preserve --same-owner @dirs";
        EBox::Sudo::root($tarCommand);
    }


} 




sub  _loadSharesFiles
{
    my ($self, $restoreDir) = @_;

    my $tarFile = $self->_sharesFilesArchive($restoreDir);

    if (-e $tarFile) {
        my $tarCommand = "/bin/tar -xf $tarFile --bzip2 --atime-preserve --absolute-names --preserve --same-owner";
        EBox::Sudo::root($tarCommand);
    }
    else {
        EBox::error("Share's files archive not found at $tarFile. Share's files will NOT be restored.\n Resuming restoring process..")
    }


}


sub  _sharesFilesArchive
{
    my ($self, $dir) = @_;
    my $archive = "$dir/shares.tar.bz2";
    return $archive;
} 


# we look for shared directories leftover from users and groups created
# between a backup and a recovery. We move them to a leftover directories 
# so the data will be safe and retrevied by root
sub _fixLeftoverSharedDirectories
{
    my ($self) = @_;


    my @leftovers = $self->_findLeftoverSharedDirectories();
    return if @leftovers == 0;

    my $leftoversDir = $self->leftoversDir();

    if (not EBox::Sudo::fileTest('-e', $leftoversDir)) {
        EBox::Sudo::root("/bin/mkdir --mode=755 $leftoversDir");
    }

    my @leftoverTypes = qw(users groups);
    foreach my $subdir (@leftoverTypes) {
        if (not EBox::Sudo::fileTest('-e', "$leftoversDir/$subdir")) {
            EBox::Sudo::root("/bin/mkdir --mode=755 $leftoversDir/$subdir");
        } 
    }

    foreach my $leftover (@leftovers) {
        my $chownCommand = "/bin/chown root.root -R $leftover";
        EBox::Sudo::root($chownCommand);

        my $chmodDirCommand = "/bin/chmod 755 $leftover";
        EBox::Sudo::root($chmodDirCommand);

        # change permission to files in dir if dir has files
        my $filesInDir = 1;
        try {  EBox::Sudo::root("/bin/ls $leftover/*")  }  otherwise { $filesInDir = 0  } ;

        if ($filesInDir) {
            my $chmodFilesCommand = "  /bin/chmod -R og-srwx  $leftover/*";
            EBox::Sudo::root($chmodFilesCommand);
        }


        my $leftoverNewDir =  $self->_leftoverNewDir($leftover, $leftoversDir);

        my $mvCommand = "/bin/mv  $leftover $leftoverNewDir";
        EBox::Sudo::root($mvCommand);
        EBox::info("Moved leftover directory $leftover to $leftoverNewDir");
    }
}


sub _leftoverNewDir
{
    my ($self, $leftover, $leftoversDir) = @_;

    my $usersPath  = EBox::SambaLdapUser::usersPath();
    my $groupsPath = EBox::SambaLdapUser::groupsPath();

    my $leftoverType;
    if ($leftover =~ m/^$usersPath/) {
        $leftoverType = 'users/';
    } 
    elsif ($leftover =~ m/^$groupsPath/) {
        $leftoverType = 'groups/';
    } 
    else {
        EBox::warn("Can not determine the type of leftover $leftover; it will be store it in $leftoversDir");
        $leftoverType = undef;	
    }

    my $leftoverNewDir = "$leftoversDir/";
    $leftoverNewDir .= $leftoverType if defined $leftoverType;  # better to store the leftover in a wrong place than lost it
        $leftoverNewDir .= File::Basename::basename($leftover);

    if (EBox::Sudo::fileTest('-e', $leftoverNewDir)) {
        EBox::warn ("$leftoverNewDir already exists, we will choose another dir for this leftover. Please, remove or store away leftover directories" );
        my $counter = 2;
        my $oldLeftoverDir =$leftoverNewDir;
        do  {
            $leftoverNewDir = $oldLeftoverDir . ".$counter";
            $counter = $counter +1 ;
        } while (EBox::Sudo::fileTest('-e', $leftoverNewDir));
        EBox::warn("The leftover will be stored in $leftoverNewDir");
    }

    return $leftoverNewDir;
}


sub _findLeftoverSharedDirectories
{
    my ($self) = @_;

    my $sambaLdapUser = new EBox::SambaLdapUser;

    my @leftovers;
    my $sharedDirs = $sambaLdapUser->sharedDirectories();
    return () if @{ $sharedDirs } == 0;


    my $usersDir =  $sambaLdapUser->usersPath();
    push @leftovers, $self->_findLeftoversInDir($usersDir, $sharedDirs);

    my $groupsDir = $sambaLdapUser->groupsPath();
    push @leftovers, $self->_findLeftoversInDir($groupsDir, $sharedDirs);

    EBox::info("Leftovers shared directories found: @leftovers") if @leftovers > 0;
    return @leftovers;
}


sub _findLeftoversInDir
{
    my ($self, $dir, $sharedDirs) = @_;
    my $allShareDirs =  all(@{ $sharedDirs }) ;

    my @candidateDirs;
    try {
        @candidateDirs = @{ EBox::Sudo::root("/usr/bin/find $dir/* -type d -maxdepth 0 ") };
    }
    catch EBox::Exceptions::Sudo::Command with { # we catch this because find will be fail if aren't any subdirectories in $dir
        @candidateDirs = ();
    };

    chomp @candidateDirs;

    my @leftovers = grep { $_ ne $allShareDirs  } @candidateDirs;
    return @leftovers;
}

sub leftoversDir
{
    return EBox::SambaLdapUser::basePath() . '/leftovers';
}


# Overrides:
#   EBox::Report::DiskUsageProvider::_facilitiesForDiskUsage
sub _facilitiesForDiskUsage
{
    my ($self) = @_;

    my $usersPrintableName  = __(q{User's files});
    my $usersPath           = EBox::SambaLdapUser::usersPath();
    my $groupsPrintableName = __(q{Group's files});
    my $groupsPath          = EBox::SambaLdapUser::groupsPath();

    return {
        $usersPrintableName   => [ $usersPath ],
        $groupsPrintableName  => [ $groupsPath ],
    };

}

1;