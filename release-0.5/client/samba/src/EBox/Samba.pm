# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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

use base qw(EBox::GConfModule EBox::LdapModule);

use EBox::Sudo qw( :all );
use EBox::Global;
use EBox::Ldap;
use EBox::SambaLdapUser;
use EBox::UsersAndGroups;
use EBox::Network;
use EBox::SambaFirewall;
use EBox::Summary::Module;
use EBox::Summary::Value;
use EBox::Summary::Status;
use EBox::Summary::Section;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Gettext;

use constant SMBCONFFILE          => '/etc/samba/smb.conf';
use constant LIBNSSLDAPFILE       => '/etc/libnss-ldap.conf';
use constant SMBINIT              => '/etc/init.d/samba';
use constant SMBPIDFILE           => '/var/run/samba/smbd.pid';
use constant NMBPIDFILE           => '/var/run/samba/nmbd.pid';
use constant MAXNETBIOSLENGTH 	  => 32;
use constant MAXWORKGROUPLENGTH   => 32;
use constant MAXDESCRIPTIONLENGTH => 255;


sub _create
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'samba',
					  domain => 'ebox-samba',
					  @_);
	bless($self, $class);
	return $self;
}

sub _setSambaConf
{
	my $self = shift;
	
	my $net = EBox::Global->modInstance('network');
	my $interfaces = join (',', @{$net->InternalIfaces}, 'lo');
	my $ldap = new EBox::Ldap;
	my $smbimpl = new EBox::SambaLdapUser;
	
	my @array = ();
	push(@array, 'netbios'   => $self->netbios);
	push(@array, 'desc'      => $self->description);
	push(@array, 'workgroup' => $self->workgroup);
	push(@array, 'ldap'      => $ldap->ldapConf);
	push(@array, 'dirgroup'  => $smbimpl->groupShareDirectories);
	push(@array, 'ifaces'    => $interfaces); 
	
	
	$self->writeConfFile(SMBCONFFILE, "samba/smb.conf.mas", \@array);

	my $ldapconf = $ldap->ldapConf;
	my $users = EBox::Global->modInstance('users');
	
	@array = ();
	push(@array, 'basedc'    => $ldapconf->{'dn'});
	push(@array, 'ldapi'     => $ldapconf->{'ldapi'});
	push(@array, 'binddn'     => $ldapconf->{'rootdn'});
	push(@array, 'bindpw'    => $ldap->rootPw);
	push(@array, 'usersdn'   => $users->usersDn);
	push(@array, 'groupsdn'  => $users->groupsDn); 
	
	$self->writeConfFile(LIBNSSLDAPFILE, "samba/libnss-ldap.conf.mas", 
					     \@array);
	
	# Set quotas
	$smbimpl->_setAllUsersQuota();
}

sub isRunning
{
	my $self = shift;
	
	return ($self->pidFileRunning(SMBPIDFILE) and 
	        $self->pidFileRunning(NMBPIDFILE));
}

sub _doDaemon
{
        my $self = shift;
        if ($self->service and $self->isRunning) {
                $self->_daemon('restart');
        } elsif ($self->service) {
                $self->_daemon('start');
        } elsif ($self->isRunning) {
                $self->_daemon('stop');
        }
}

sub _daemon
{
	my ($self, $action) = @_;
        my $command =  SMBINIT . " " . $action . " 2>&1";

        if ( $action eq 'start') {
                root($command);
        } elsif ( $action eq 'stop') {
                root($command);
        } elsif ( $action eq 'reload') {
                root($command);
        } elsif ( $action eq 'restart') {
                root($command);
        } else {
     		throw EBox::Exceptions::Internal("Bad argument: $action");
        }
}

sub _stopService
{
	my $self = shift;
	if ($self->isRunning) {
		$self->_daemon('stop');
	}
}

sub _regenConfig
{
	my $self = shift;
	$self->_setSambaConf;
	$self->_doDaemon();
}

sub firewallHelper
{
	my $self = shift;
	if ($self->service) {
		return new EBox::SambaFirewall();
	}
	return undef;
}

sub statusSummary
{
	my $self = shift;
	return new EBox::Summary::Status('samba', __('File sharing'),
					$self->isRunning, $self->service);
}

sub rootCommands 
{
	my $self = shift;
	my @array = ();
	push(@array, SMBINIT);
	push(@array, "/bin/chmod * " . SMBCONFFILE);
	push(@array, "/bin/chown * " . SMBCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . SMBCONFFILE);
	push(@array, "/bin/chmod * " . LIBNSSLDAPFILE);
	push(@array, "/bin/chown * " . LIBNSSLDAPFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . LIBNSSLDAPFILE);
	push(@array, "/bin/mkdir " . USERSPATH . "/*");
	push(@array, "/bin/chown * " . USERSPATH . "/*");
	push(@array, "/bin/chmod * " . USERSPATH . "/*");
	push(@array, "/bin/rm -rf " . USERSPATH. "/*");
	push(@array, "/bin/mkdir " . GROUPSPATH . "/*");
	push(@array, "/bin/chown * " . GROUPSPATH . "/*");
	push(@array, "/bin/chmod * " . GROUPSPATH . "/*");
	push(@array, "/bin/rm -rf " . GROUPSPATH. "/*");
	push(@array, "/usr/sbin/setquota *");

	return @array;
}



sub setService # (enabled) 
{
        my ($self, $active) = @_;
        ($active and $self->service) and return;
        (!$active and !$self->service) and return;
        $self->set_bool('active', $active);
}
#returns if service is active or not
#ret: bool
sub service
{
        my $self = shift;
        return $self->get_bool('active');
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
#ret: bool
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

#returns description name
#ret: bool
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
#ret: bool
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
#ret: bool
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

1;
