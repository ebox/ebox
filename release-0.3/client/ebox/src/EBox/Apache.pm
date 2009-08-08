# Copyright (C) 2004  Warp Netwoks S.L.
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

package EBox::Apache;

use strict;
use warnings;

use base 'EBox::GConfModule';

use EBox::Validate qw( :all );
use EBox::Sudo qw( :all );
use POSIX qw(setsid);
use EBox::Global;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataInUse;
use EBox::Exceptions::DataMissing;
use EBox::Gettext;

sub _create {
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'apache');
	bless($self, $class);
	return $self;
}

# restarting apache from inside apache could be problematic, so we fork() and
# detach the child from the process group.
sub _daemon() {
	shift;
	my $action = shift;
	my $pid;
	my $sleep = undef;
	exists $ENV{"MOD_PERL"} and $sleep = 1;

	unless (defined($pid = fork())) {
		throw EBox::Exceptions::Internal("Cannot fork().");
	}
	
	if ($pid) { 
		return; # parent returns inmediately
	}

	POSIX::setsid();

	$sleep and sleep(5);

	if ($action eq 'stop') {
		root("/etc/init.d/apache-perl stop");
	} elsif ($action eq 'start') {
		root("/etc/init.d/apache-perl start");
	} elsif ($action eq 'restart') {
		root("/etc/init.d/apache-perl stop");
		sleep 6;
		root("/etc/init.d/apache-perl start");
	}
	exit 0;
}

sub _stopService {
	my $self = shift;
	$self->_daemon('stop');
}

sub _regenConfig {
	my $self = shift;
	my $port = $self->port;
	open(APACHE, ">" . EBox::Config::conf . "/apacheport.conf") or
		throw EBox::Exceptions::Internal("Cannot open the apache port ".
						"file.");
	print APACHE "Port $port\n";
	close(APACHE);
	$self->_daemon('restart');
}

sub port($) {
	my $fw = EBox::Global->modInstance('firewall');
	return $fw->servicePort("administration");
}

sub setPort($$) {
	my ($self, $port) = @_;
	checkPort($port, "port");
	my $fw = EBox::Global->modInstance('firewall');
	my $currentport = $fw->servicePort("administration");
	if ($currentport == $port) {
		return;
	}
	unless ($fw->availablePort($port)) {
		throw EBox::Exceptions::DataInUse(data => __('port'),
						  value => $port);
	}

	$fw->changeService("administration", "tcp", $port);
	my $global = EBox::Global->getInstance();
	$self->_backup;
	$global->modChange($self->name);
}

1;
