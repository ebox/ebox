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

package EBox::Module;

use strict;
use warnings;

use File::Copy;
use EBox::Config;
use EBox::Global;
use EBox::Exceptions::Internal;
use EBox::Gettext;
use Fcntl qw(:flock);
use Error qw(:try);


## options:
##		name [required]
sub _create {
	my $class = shift;
	my %opts = @_;
	my $self = {};
	$self->{name} = delete $opts{name};
	$self->{domain} = delete $opts{domain};
	unless (defined($self->{name})) {
		use Devel::StackTrace;
		my $trace = Devel::StackTrace->new;
		print STDERR $trace->as_string;
		throw EBox::Exceptions::Internal(
			"No name provided on Module creation");
	}
	bless($self, $class);
	return $self;
}

sub revokeConfig($) {
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

sub _saveConfig($) {
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

sub _regenConfig {
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

sub restartService($) {
	my $self = shift;

	$self->_lock();
	my $global = EBox::Global->getInstance();
	my $log = EBox::Global->logger;
	$log->info("Restarting service for module: " . $self->name);
	try {
		$self->_regenConfig;
	} finally {
		$global->modRestarted($self->name);
		$self->_unlock();
	};
}

sub _unlock($) {
	my $self = shift;
	flock(LOCKFILE, LOCK_UN);
	close(LOCKFILE);
}

sub _lock($) {
	my $self = shift;
	my $file = EBox::Config::tmp . "/" . $self->name . ".lock";
	open(LOCKFILE, ">$file") or
		throw EBox::Exceptions::Internal("Cannot open lockfile: $file");
	flock(LOCKFILE, LOCK_EX | LOCK_NB) or
		throw EBox::Exceptions::Lock($self);
}

sub _stopService($) {
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

sub stopService($) {
	my $self = shift;

	$self->_lock();
	try {
		$self->_stopService();
	} finally {
		$self->_unlock();
	};
}

# arguments
# 	- the name of an Object
# returns
# 	- true: if this module currently uses the object
#	- false: if this module does not use the object
sub usesObject($$) {
	# default implementation: always returns false. Subclasses should
	# override this as needed.
	return undef;
}

# Tells this module that an object is going to be removed, so that it can remove it
# from its configuration.
# arguments
# 	- the name of an Object, which is about to be removed
sub freeObject($$) {
	# default empty implementation. Subclasses should override this as
	# needed.
}

sub name {
	my $self = shift;
	return $self->{name};
}

sub setName {
	my $self = shift;
	my $name = shift;
	$self->{name} = $name;
}

sub summary() {
	# default empty implementation
	return undef;
}

sub domain($) {
	my $self = shift;

	if (defined $self->{domain}){
		return $self->{domain};
	} else {
		return 'ebox';
	}
}
1;
