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

use base qw(EBox::GConfModule Apache::Singleton Apache::AuthCookie);

use EBox::Validate qw( :all );
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataInUse;
use EBox::Config;
use Log::Log4perl;

use Digest::MD5;

#redefine inherited method to create own constructor
#for Singleton pattern
sub _new_instance {
	my $class = shift;
	my $self  = bless { }, $class;
	$self->{'global'} = _create EBox::Global;
	return $self;
}

sub _create {
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'global');
	bless($self, $class);
	$self->{'mod_instances'} = {};
	$self->{'mod_instances'}->{'global'} = $self;
	return $self;
}

# arguments
# 	- string: name of a module
# returns
# 	- true:  if the module exists
# 	- false: if the module does not exist
sub modExists($$) {
	my ($self, $name) = @_;
	return $self->dir_exists("modules/$name");
}

# arguments
# 	- string: name of a module
# returns
# 	- true - module config has been changed
# 	- false - module config has not been changed
sub modIsChanged($$) {
	my ($self, $name) = @_;
	defined($name) or return undef;
	($name ne 'global') or return undef;
	$self->modExists($name) or return undef;
	return $self->get_bool("modules/$name/changed");
}

# arguments
# 	- string: name of a module
sub modChange($$) {
	my ($self, $name) = @_;
	defined($name) or return;
	($name ne 'global') or return;
	$self->modExists($name) or return;
	$self->set_bool("modules/$name/changed", 1);
}

# arguments
# 	- string: name of a module
sub modRestarted($$) {
	my ($self, $name) = @_;
	defined($name) or return;
	($name ne 'global') or return;
	$self->modExists($name) or return;
	$self->set_bool("modules/$name/changed", undef);
}

# returns
# 	- array containing all module names
sub modNames($) {
	my $self = shift;
	return $self->all_dirs_base("modules");
}

# returns
# 	- true: if there is at least one unsaved module
# 	- false if there are no unsaved modules
sub unsaved($) {
	my $self = shift;
	my @names = $self->modNames;
	foreach (@names) {
		$self->modIsChanged($_) or next;
		return 1;
	}
	return undef;
}

sub revokeAllModules($) {
	my $self = shift;
	my @names = $self->modNames;

	foreach (@names) {
		$self->modIsChanged($_) or next;
		my $mod = $self->modInstance($_);
		$mod->revokeConfig;
	}
}

sub saveAllModules($) {
	my $self = shift;
	my @names = $self->modNames;
	my @mods = ();
	my $log = $self->logger;
	my $msg = "Saving config and restarting services: ";

	foreach (@names) {
		$self->modIsChanged($_) or next;

		push(@mods, $_);
		$msg .= "$_ ";

		my @deps = $self->modRevDepends($_);
		foreach (@deps) {
			my $aux = $_;
			unless (grep(/^$aux$/, @mods)) {
				push(@mods, $_);
				$msg .= "$_ ";
			}
		}
	}
	$log->info($msg);

	foreach (@mods) {
		my $mod = $self->modInstance($_);
		$mod->restartService();
	}
}

sub restartAllModules($) {
	my $self = shift;
	my @names = $self->modNames;
	my $log = $self->logger;
	$log->info("Restarting all modules");
	foreach (@names) {
		my $mod = $self->modInstance($_);
		$mod->restartService();
	}
}

sub stopAllModules($) {
	my $self = shift;
	my @names = $self->modNames;
	my $log = $self->logger;
	$log->info("Stopping all modules");
	foreach (@names) {
		my $mod = $self->modInstance($_);
		$mod->stopService();
	}
}


# Builds and instance of a module. Can be called as a class method or as an
# object method.
# arguments
# 	- string: the name of a module
# returns
# 	- undef: if there is no module with that name
#       - an EBox::Module instance of the requested type
sub modInstance($$) {
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
		$global->{'mod_instances'}->{$name} = $classname->_create;
		return $global->{'mod_instances'}->{$name};
	}

}

# initializes Log4perl if necessary, returns the logger for the caller package
sub logger {
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
sub modDepends($$) {
	my ($self, $name) = @_;
	$self->modExists($name) or return undef;
	my $list = $self->get_list("modules/$name/depends");
	if ($list) {
		return @{$list};
	} else {
		return ();
	}
}

# arguments
# 	- string: the name of a module
# returns
#	- undef: if the module does not exist
#	- an array with the names of all modules which depend on this module
sub modRevDepends($$) {
	my ($self, $name) = @_;
	$self->modExists($name) or return undef;
	my @revdeps = ();
	my @mods = $self->modNames;
	foreach my $mod (@mods) {
		my @deps = $self->modDepends($mod);
		foreach my $dep (@deps) {
			defined($dep) or next;
			if ($name eq $dep) {
				push(@revdeps, $mod);
				last;
			}
		}
	}
	return @revdeps;
}

# Unregisters a module from the global configuration, if there are no modules
# that depend on it.
# arguments
# 	- string: the name of a module
# returns
#	- true: if the module was successfully removed
#	- false: if there are modules that depend on it
sub unregisterMod($$) {
	my ($self, $name) = @_;
	$self->modExists($name) or
		throw EBox::Exceptions::DataNotFound('data' => 'module',
						     'value' => $name);
	my @deps = $self->modRevDepends($name);

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
sub menuEntries($) {
	my $self = shift;
	my @mods = $self->modNames;
	my @array = ();
	foreach (@mods) {
		my @entries = $self->all_dirs("modules/$_/menu");
		foreach (@entries) {
			my @entry = ();
			push(@entry, $self->get_string("$_/text"));
			push(@entry, $self->get_string("$_/location"));
			push(@entry, $self->get_string("$_/order"));
			push(@entry, $self->get_string("$_/style"));
			push(@array, \@entry);
		}
	}
	return \@array;
}

# arguments
# 	- string: the name of a module
# returns
#	- undef: if the module does not exist
#	- an array with all the test module names for the given module
sub modTests($$) {
	my ($self, $name) = @_;
	# TODO
}

# arguments
# 	- locale: the locale the interface should use
sub setLocale($$) {
	my ($self, $locale) = @_;
#	do some check
#	checkLocale($locale) or
#		throw EBox::Exceptions::InvalidData('data' => 'locale',
#						    'value' => $locale);
	$self->set_string("lang", $locale);
}

# returns:
# 	- the port number on which the admin interface is listening
sub locale($) {
	my $self = shift;
	return $self->get_string("lang");
}

1;
