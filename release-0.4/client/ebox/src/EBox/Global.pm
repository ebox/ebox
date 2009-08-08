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

package EBox::Global;

use strict;
use warnings;

use base qw(EBox::GConfModule Apache::Singleton);

use EBox::Validate qw( :all );
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataInUse;
use Error qw(:try);
use EBox::Config;
use EBox::Gettext;
use Log::Log4perl;
use POSIX qw(setuid setgid setlocale LC_ALL);


use Digest::MD5;

#redefine inherited method to create own constructor
#for Singleton pattern
sub _new_instance 
{
	my $class = shift;
	my $self  = bless { }, $class;
	$self->{'global'} = _create EBox::Global;
	return $self;
}

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'global');
	bless($self, $class);
	$self->{'mod_instances'} = {};
	$self->{'mod_instances'}->{'global'} = $self;
	return $self;
}

sub isReadOnly
{
	my $self = shift;
	return $self->{ro};
}

sub makeBackup # (dir) 
{
	my ($self, $dir) = @_;
}

sub restoreBackup # (dir) 
{
	my ($self, $dir) = @_;
}

# arguments
# 	- string: name of a module
# returns
# 	- true:  if the module exists
# 	- false: if the module does not exist
sub modExists # (module) 
{
	my ($self, $name) = @_;
	return $self->dir_exists("modules/$name");
}

# arguments
# 	- string: name of a module
# returns
# 	- true - module config has been changed
# 	- false - module config has not been changed
sub modIsChanged # (module) 
{
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne 'global') or return undef;
	$self->modExists($name) or return undef;
	return $self->get_bool("modules/$name/changed");
}

# arguments
# 	- string: name of a module
sub modChange # (module) 
{
	my ($self, $name) = @_;
	defined($name) or return;
	($name ne 'global') or return;
	$self->modExists($name) or return;
	$self->set_bool("modules/$name/changed", 1);
}

# arguments
# 	- string: name of a module
sub modRestarted # (module) 
{
	my ($self, $name) = @_;
	defined($name) or return;
	($name ne 'global') or return;
	$self->modExists($name) or return;
	$self->set_bool("modules/$name/changed", undef);
}

# returns
# 	- array containing all module names
sub modNames
{
	my $self = shift;
	return $self->all_dirs_base("modules");
}

# returns
# 	- true: if there is at least one unsaved module
# 	- false if there are no unsaved modules
sub unsaved
{
	my $self = shift;
	my @names = @{$self->modNames};
	foreach (@names) {
		$self->modIsChanged($_) or next;
		return 1;
	}
	return undef;
}

sub revokeAllModules
{
	my $self = shift;
	my @names = @{$self->modNames};
	my $failed = "";

	foreach my $name (@names) {
		$self->modIsChanged($name) or next;
		my $mod = $self->modInstance($name);
		try {
			$mod->revokeConfig;
		} catch EBox::Exceptions::Internal with {
			$failed .= "$name ";
		};
	}
	if ($failed eq "") {
		return;
	}
	throw EBox::Exceptions::Internal("The following modules failed while ".
		"revoking their changes, their state is unknown: $failed");
}

sub saveAllModules
{
	my $self = shift;
	my @names = @{$self->modNames};
	my @mods = ();
	my $log = $self->logger;
	my $msg = "Saving config and restarting services: ";
	my $failed = "";
	
	push(@mods, 'firewall');
	foreach my $modname (@names) {
		$self->modIsChanged($modname) or next;

		unless (grep(/^$modname$/, @mods)) {
			push(@mods, $modname);
			$msg .= "$modname ";
		}
		
		my @deps = @{$self->modRevDepends($modname)};
		foreach my $aux (@deps) {
			unless (grep(/^$aux$/, @mods)) {
				push(@mods, $aux);
				$msg .= "$aux ";
			}
		}
	}
	$log->info($msg);

	my $apache = 0;
	foreach my $name (@mods) {
		if ($_ eq 'apache') {
			$apache = 1;
			next;
		}
		my $mod = $self->modInstance($name);
		try {
			$mod->restartService();
		} catch EBox::Exceptions::Internal with {
			$failed .= "$name ";
		};
	}

	# FIXME - tell the CGI to inform the user that apache is restarting
	if ($apache) {
		my $mod = $self->modInstance('apache');
		try {
			$mod->restartService();
		} catch EBox::Exceptions::Internal with {
			$failed .= "apache";
		};

	}
	
	if ($failed eq "") {
		return;
	}
	throw EBox::Exceptions::Internal("The following modules failed while ".
		"saving their changes, their state is unknown: $failed");
}

sub restartAllModules
{
	my $self = shift;
	my @names = @{$self->modNames};
	my $log = $self->logger;
	my $failed = "";
	$log->info("Restarting all modules");
	foreach my $name (@names) {
		my $mod = $self->modInstance($name);
		try {
			$mod->restartService();
		} catch EBox::Exceptions::Internal with {
			$failed .= "$name ";
		};

	}
	if ($failed eq "") {
		return;
	}
	throw EBox::Exceptions::Internal("The following modules failed while ".
		"being restarted, their state is unknown: $failed");
}

sub stopAllModules
{
	my $self = shift;
	my @names = @{$self->modNames};
	my $log = $self->logger;
	my $failed = "";
	$log->info("Stopping all modules");
	foreach my $name (@names) {
		my $mod = $self->modInstance($name);
		try {
			$mod->stopService();
		} catch EBox::Exceptions::Internal with {
			$failed .= "$name ";
		};

	}
	
	if ($failed eq "") {
		return;
	}
	throw EBox::Exceptions::Internal("The following modules failed while ".
		"stopping, their state is unknown: $failed");

}

sub getInstance # (read_only?) 
{
	shift;
	my $ro = shift;
	my $global = EBox::Global->instance->{'global'};
	if ($ro) {
		$global->{ro} = 1;
	}
	return $global;
}


# Builds and instance of a module. Can be called as a class method or as an
# object method.
# arguments
# 	- string: the name of a module
# returns
# 	- undef: if there is no module with that name
#       - an EBox::Module instance of the requested type
sub modInstance # (module) 
{
	shift;
	my $name = shift;
	my $global = EBox::Global->instance->{'global'};
	if (defined($global->{'mod_instances'}->{$name})) {
		return $global->{'mod_instances'}->{$name};
	} else {
		$global->modExists($name) or return undef;
		my $classname = $global->get_string("modules/$name/class");
		eval "use $classname";
		if ($@) {
			throw EBox::Exceptions::Internal("Error loading ".
							 "class: $classname");
		}
		if ($global->isReadOnly()) {
			$global->{'mod_instances'}->{$name} =
						$classname->_create(ro => 1);
		} else {
			$global->{'mod_instances'}->{$name} =
							$classname->_create;
		}
		return $global->{'mod_instances'}->{$name};
	}

}

# initializes Log4perl if necessary, returns the logger for the caller package
sub logger # (caller?) 
{
	shift;
	my $cat = shift;
	defined($cat) or $cat = caller;
	my $global = EBox::Global->instance->{'global'};
	unless ($global->{logger}) {
		Log::Log4perl->init_and_watch(
			EBox::Config::conf .  "/eboxlog.conf", 60);
		$global->{logger} = 1;
	}
	return Log::Log4perl->get_logger($cat);
}

# arguments
# 	- string: the name of a module
# returns
# 	- undef: if the module does not exist
# 	- an array with the names of the modules that the requested module
# 	  depends on.
sub modDepends # (module) 
{
	my ($self, $name) = @_;
	$self->modExists($name) or return undef;
	my $list = $self->get_list("modules/$name/depends");
	if ($list) {
		return $list;
	} else {
		return [];
	}
}

# arguments
# 	- string: the name of a module
# returns
#	- undef: if the module does not exist
#	- an array with the names of all modules which depend on this module
sub modRevDepends # (module) 
{
	my ($self, $name) = @_;
	$self->modExists($name) or return undef;
	my @revdeps = ();
	my @mods = @{$self->modNames};
	foreach my $mod (@mods) {
		my @deps = @{$self->modDepends($mod)};
		foreach my $dep (@deps) {
			defined($dep) or next;
			if ($name eq $dep) {
				push(@revdeps, $mod);
				last;
			}
		}
	}
	return \@revdeps;
}

# Unregisters a module from the global configuration, if there are no modules
# that depend on it.
# arguments
# 	- string: the name of a module
# returns
#	- true: if the module was successfully removed
#	- false: if there are modules that depend on it
sub unregisterMod # (module) 
{
	my ($self, $name) = @_;
	$self->modExists($name) or
		throw EBox::Exceptions::DataNotFound('data' => 'module',
						     'value' => $name);
	my @deps = @{$self->modRevDepends($name)};

	if (@deps > 0) {
		return undef;
	}

	$self->delete_dir("/ebox/global/modules/$name");
	$self->delete_dir("/schemas/ebox/global/modules/$name");
	return 1;
}

# returns
#	- a two-dimensional array containing text, location,
#	  order and style in each row.
sub menuEntries
{
	my $self = shift;
	my @mods = @{$self->modNames};
	my @array = ();
	foreach (@mods) {
		my @entries = $self->all_dirs("modules/$_/menu");
		foreach (@entries) {
			my $entry;
			$entry->{'text'} = $self->get_string("$_/text");
			$entry->{'location'} = $self->get_string("$_/location");
			$entry->{'order'} = $self->get_string("$_/order");
			$entry->{'style'} = $self->get_string("$_/style");
			if($self->dir_exists("$_/sub/")) {
				my @subEntries = $self->all_dirs("$_/sub");
				my @subArray = ();
				foreach (@subEntries) {
					my $subEntry;
					$subEntry->{'text'} = $self->get_string("$_/text");
					$subEntry->{'location'} = $self->get_string("$_/location");
					push(@subArray, $subEntry);
				}
				$entry->{'sub'} = \@subArray;
			}
			push(@array, $entry);
		}
	}
	return \@array;
}

# arguments
# 	- string: the name of a module
# returns
#	- undef: if the module does not exist
#	- an array with all the test module names for the given module
sub modTests # (module) 
{
	my ($self, $name) = @_;
	# TODO
}

# arguments
# 	- locale: the locale the interface should use
sub setLocale # (locale) 
{
	shift;
	my $locale = shift;
#	do some check
#	checkLocale($locale) or
#		throw EBox::Exceptions::InvalidData('data' => 'locale',
#						    'value' => $locale);
	open(LOCALE, ">".EBox::Config::conf . "/locale");
	print LOCALE $locale;
	close(LOCALE);
}

# returns:
# 	- the port number on which the admin interface is listening
sub locale 
{
	my $locale="C";
	if (-f EBox::Config::conf . "/locale") {
		open(LOCALE, EBox::Config::conf . "/locale");
		$locale = <LOCALE>;
		close(LOCALE);
	}
	return $locale;
}

sub init
{
	POSIX::setlocale(LC_ALL, EBox::Global::locale());
	my $user = EBox::Config::user;
	my $group = EBox::Config::group;
	my $uid = getpwnam($user);
	my $gid = getgrnam($group);
	setgid($gid) or die "Cannot change group to $group";
	setuid($uid) or die "Cannot change user to $user";
}

sub rootCommands
{
	my $self = shift;
	my @array = ();
	push(@array, '/sbin/halt');
	push(@array, '/sbin/reboot');
	return @array;
}

1;
