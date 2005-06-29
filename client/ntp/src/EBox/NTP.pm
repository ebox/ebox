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

package EBox::NTP;

use strict;
use warnings;

use base 'EBox::GConfModule';

use EBox::Objects;
use EBox::Gettext;
use EBox::Summary::Module;
use EBox::Summary::Section;
use EBox::Summary::Status;
use EBox::Summary::Value;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use Error qw(:try);
use EBox::Validate qw( :all );
use EBox::Sudo qw( :all );
use EBox;

use constant NTPCONFFILE => "/etc/ntp.conf";
use constant NTPINIT     => "/etc/init.d/ntp-server";
use constant PIDFILE       => "/var/run/ntpd.pid";

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'ntp', 
						domain => 'ebox-ntp',
						@_);
	bless($self, $class);
	return $self;
}

sub isRunning
{
   my $self = shift;
   return $self->pidFileRunning(PIDFILE);
}


sub _doDaemon
{
   my $self = shift;
	my $logger = EBox::logger();

  if (($self->service or $self->synchronized) and $self->isRunning) {
      $self->_daemon('stop');
		sleep 2;
		if ($self->synchronized) {
			my $exserver = $self->get_string('server1');
			try { 
				root("/usr/sbin/ntpdate $exserver");
			} catch EBox::Exceptions::Internal with {
				$logger->info("Error no se pudo lanzar ntpdate");
			};
		}
      $self->_daemon('start');
   } elsif ($self->service or $self->synchronized) {    
		if ($self->synchronized) {
			my $exserver = $self->get_string('server1');
			try { 
				root("/usr/sbin/ntpdate $exserver");
			} catch EBox::Exceptions::Internal with {
				$logger->info("Error no se pudo lanzar ntpdate");
			};
		}
      $self->_daemon('start');
   } elsif ($self->isRunning) {
		$self->_daemon('stop');
		if ($self->synchronized) {
			$self->_daemon('start');
		}
   }
}

sub _stopService
{
	my $self = shift;

	if ($self->isRunning) {
	$self->_daemon('stop');
	}
}

sub _configureFirewall($){
	my $self = shift;
	my $fw = EBox::Global->modInstance('firewall');
	
	if ($self->synchronized) {
		$fw->addOutputRule('udp', 123);
	} else {
		$fw->removeOutputRule('udp', 123);
	}
	
	if ($self->service and (!defined($fw->service('ntp')))) {
		$fw->addService('ntp', 'udp', 123, 0);
		$fw->setObjectService('_global', 'ntp', 'allow');
	} elsif ( !($self->service) and defined($fw->service('ntp')) ) {
		$fw->removeService('ntp');
	}
}

# Method: setService 
#
#       Enable/Disable the ntp service 
#
# Parameters:
#
#       enabled - boolean. True enable, undef disable
#       
sub setService # (active)
{
	my ($self, $active) = @_;
	($active and $self->service) and return;
	(!$active and !$self->service) and return;
	$self->set_bool('active', $active);
	$self->_configureFirewall;
}

# Method: service               
#               
#       Returns if the ntp service is enabled  
#                       
# Returns:      
#       
#       boolean - true if enabled, otherwise undef
sub service
{
   my $self = shift;
   return $self->get_bool('active');
}

# Method: setSynchronized
#
#      Enable/disable the synchronization service to external ntp servers
#
# Parameters:
#
#       enabled - boolean. True enable, undef disable
#
sub setSynchronized # (synchro)
{
	my $self = shift;
	my $synchronized = shift;

	($synchronized and $self->synchronized) and return;
	(!$synchronized and !$self->synchronized) and return;
	$self->set_bool('synchronized', $synchronized);
	$self->_configureFirewall;
}

# Method: synchronized
#
#      Enable/disable the synchronization service to external ntp servers
#
# Returns:
#
#      boolean -  True enable, undef disable
#
sub synchronized
{
	my $self = shift;
	return $self->get_bool('synchronized');
}

# Method: setServers
#
#	Sets the external ntp servers to synchronize from
#
# Parameters:
#
#	server1 - primary server
#	server2 - secondary server
#	server3 - tertiary server
#
sub setServers # (server1, server2, server3)
{
	my $self = shift;
	my $s1 = shift;
	my $s2 = shift;
	my $s3 = shift;

	if ($s1 =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
		checkIP($s1, __("primary server IP address"));
		$self->set_string('server1', $s1);
	} else {
		checkDomainName($s1, __("primary server name ")); 
		$self->set_string('server1', $s1);
	}
	
	if (defined($s2) and ($s2 ne "")) {
		if ($s2 =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
			checkIP($s2, __("secondary server IP address"));
			$self->set_string('server2', $s2);
		} else {
			checkDomainName($s2,  __("secondary server name"));
			$self->set_string('server2', $s2);

			if (defined($s3) and ($s3 ne "")) {
				if ($s3 =~ /^(\d{1,3}\.){3}\d{1,3}$/) {
					checkIP($s3, __("tertiary server IP address"));
					$self->set_string('server3', $s3);
				} else {
					checkDomainName($s3,  __("tertiary server name"));
					$self->set_string('server3', $s3);
				}
			} else {
					$self->set_string('server3', "");
			}
		}
	} elsif (defined($s3) and ($s3 ne "")) {
		throw EBox::Exceptions::DataMissing ('data' => __('Secondary server'));
	} else {
		$self->set_string('server2', "");
		$self->set_string('server3', "");
	}
}

# Method: servers 
#
#	Returns the list of external ntp servers
#
# Returns:
#
#	array - holding the ntp servers
sub servers {
	my $self = shift;
	my @servers;
	
	@servers = ($self->get_string('server1'),	$self->get_string('server2'),
	$self->get_string('server3'));

	return @servers;
}

# Method: _regenConfig
#
#       Overrides base method. It regenertates the configuration
#       for squid and dansguardian.
#
sub _regenConfig
{
	my $self = shift;

	$self->_setNTPConf;
	$self->_doDaemon();
}

sub _setNTPConf
{
	my $self = shift;
	my @array = ();
	my @servers = $self->servers;
	my $synch = 'no';
	my $active = 'no';
	
	($self->synchronized) and $synch = 'yes';
	($self->service) and $active = 'yes';

	push(@array, 'active'	=> $active);
	push(@array, 'synchronized'  => $synch);
	push(@array, 'servers'  => \@servers);

	$self->writeConfFile(NTPCONFFILE, "ntp/ntp.conf.mas", \@array);
}

sub _daemon # (action)
{
	my ($self, $action) = @_;

	if ( $action eq 'start') {
		root("start-stop-daemon --start --quiet --pidfile /var/run/ntpd.pid --exec /usr/sbin/ntpd -- -g -p /var/run/ntpd.pid");
	} elsif ( $action eq 'stop') {
		root("start-stop-daemon --stop --quiet --pidfile /var/run/ntpd.pid");
	} elsif ( $action eq 'force-reload') {
		root("start-stop-daemon --stop --quiet --pidfile /var/run/ntpd.pid");
		sleep 2;
		root("start-stop-daemon --start --quiet --exec /usr/sbin/ntpd -- -g -p /var/run/ntpd.pid");
	} else {
		throw EBox::Exceptions::Internal("Bad argument: $action");
	}
}

sub _restartAllServices
{
	my $self = shift;
	my $global = EBox::Global->getInstance();
	my @names = grep(!/^network$/, @{$global->modNames});
	@names = grep(!/^firewall$/, @names);
	my $log = EBox::logger();
	my $failed = "";
	$log->info("Restarting all modules");
	foreach my $name (@names) {
		my $mod = $global->modInstance($name);
		try {
			$mod->restartService();
		} catch EBox::Exceptions::Internal with {
			$failed .= "$name ";
		};
	}
	if ($failed ne "") {
		throw EBox::Exceptions::Internal("The following modules ".
			"failed while being restarted, their state is ".
			"unknown: $failed");
	}
	
	$log->info("Restarting system logs");
	try {
		root("/etc/init.d/sysklogd restart");
		root("/etc/init.d/klogd restart");
		root("/etc/init.d/cron restart");
	} catch EBox::Exceptions::Internal with {
	};
	
}

# Method: setNewDate
#
#	Sets the system date
#
# Parameters:
#
#	day - 
#	month -
#	year -
#	hour -
#	minute -
#	second -
sub setNewDate # (day, month, year, hour, minute, second)
{
	my $self = shift;
	my $day = shift;
	my $month = shift;
	my $year =  shift;
	my $hour = shift;
	my $minute = shift;
	my $second = shift;

	my $newdate = "$year-$month-$day $hour:$minute:$second";
	my $command = "/bin/date --set \"$newdate\"";
	root($command);

	my $global = EBox::Global->getInstance(1);
	$self->_restartAllServices;
}

# Method: setNewTimeZone
#
#	Sets the system's time zone 
#
# Parameters:
#
#	continent - 
#	country -
sub setNewTimeZone # (continent, country))
{
	my $self = shift;
	my $continent = shift;
	my $country = shift;

	my $command = "ln -s /usr/share/zoneinfo/$continent/$country /etc/localtime";
	$self->set_string('continent', $continent);
	$self->set_string('country', $country);
	root("rm /etc/localtime");
	root($command);
	my $global = EBox::Global->getInstance(1);
	$self->_restartAllServices;
}	

sub statusSummary
{
	my $self = shift;
	return new EBox::Summary::Status('ntp', __('NTP local server'),
					$self->isRunning, $self->service);
}

# Method: rootCommands 
#
#       Overrides EBox::Module method.
#
sub rootCommands
{
	my $self = shift;
	my @array = ();

	push(@array,"/bin/mv ".EBox::Config::tmp ."* ".NTPCONFFILE);
	push(@array, "/usr/sbin/ntpdate *");
	push(@array, "/sbin/start-stop-daemon --start --quiet --pidfile /var/run/ntpd.pid --exec /usr/sbin/ntpd -- -g -p /var/run/ntpd.pid");
	push(@array, "/sbin/start-stop-daemon --stop --quiet --pidfile /var/run/ntpd.pid");
	push(@array, "/sbin/start-stop-daemon --start --quiet --exec /usr/sbin/ntpd -- -g -p /var/run/ntpd.pid");
	push(@array, "/bin/date");
	push(@array, "/bin/rm /etc/localtime");
	push(@array, "/bin/ln -s /usr/share/zoneinfo/* /etc/localtime");
	push(@array, "/bin/chmod 0644 /etc/ntp.conf");
	push(@array, "/bin/chown 0.0 /etc/ntp.conf");
	push(@array, "/etc/init.d/sysklogd restart");
	push(@array, "/etc/init.d/klogd restart");
	push(@array, "/etc/init.d/cron restart");

	push(@array, "/bin/true");
	return @array;
}

# Method: menu 
#
#       Overrides EBox::Module method.
#
sub menu
{
        my ($self, $root) = @_;
        my $folder = new EBox::Menu::Folder('name' => 'NTP',
                                            'text' => __('NTP'));

        $folder->add(new EBox::Menu::Item('url' => 'NTP/Index',
                                          'text' => __('NTP server')));
        $folder->add(new EBox::Menu::Item('url' => 'NTP/Datetime',
                                          'text' => __('Date/time')));
        $folder->add(new EBox::Menu::Item('url' => 'NTP/Timezone',
                                          'text' => __('Time zone')));
        $root->add($folder);
}

1;
