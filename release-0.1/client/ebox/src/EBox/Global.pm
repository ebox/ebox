package EBox::Global;

use strict;
use warnings;

use base qw(EBox::XMLModule Apache::Singleton Apache::AuthCookie);

use EBox::Validate qw( :all );
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataInUse;
use XML::Simple;
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
	my $self = $class->SUPER::_create(name => 'global',
					  keyattr => {module => 'name'});
	bless($self, $class);
	$self->{'mod_instances'} = {};
	$self->{'mod_instances'}->{'global'} = $self;
	return $self;
}


# Registers a new module, whose name, classname, menu entries, tests,
# dependencies, etc. are defined in an xml file.
# arguments
# 	- the filename of module definition file
sub installMod($$) {
	my ($self, $file) = @_;
	my $xs = new XML::Simple();
	my $doc = $xs->XMLin($file, ForceArray => 1, KeepRoot => 1,
				    KeyAttr => "");

	my $name = $doc->{module}[0]->{name};
	if ($self->modExists($name)) {
		throw EBox::Exceptions::DataInUse('data' => 'module',
						  'value' => $name);
	}

	unless (defined($self->adoc->{module})) {
		$self->adoc->{module} = ();
	}

	push(@{$self->adoc->{module}}, $doc->{module}[0]);
	$self->writeArrayFile;
}

sub _newfilename($) {
	my $self = shift;
	return $self->filename;
}

# arguments
# 	- string: name of a module
# returns
# 	- true:  if the module exists
# 	- false: if the module does not exist
sub modExists($$) {
	my ($self, $name) = @_;
	return defined($self->hdoc->{module}->{$name});
}

# arguments
# 	- string: name of a module
# returns
# 	- true - module config has been changed
# 	- false - module config has not been changed
sub modIsChanged($$) {
	my ($self, $name) = @_;

	if ($name eq 'global') {
		return undef;
	}

	$self->modExists($name) or return undef;

	if ($self->hdoc->{module}->{$name}->{changed} eq 'yes') {
		return 1;
	} else {
		return undef;
	}
}

# arguments
# 	- string: name of a module
sub modChange($$) {
	my ($self, $name) = @_;

	if ($name eq 'global') {
		return;
	}

	$self->modExists($name) or return;

	$self->hdoc->{module}->{$name}->{changed} = 'yes';
	$self->writeHashFile;
}

# arguments
# 	- string: name of a module
sub modRestarted($$) {
	my ($self, $name) = @_;

	if ($name eq 'global') {
		return;
	}

	$self->modExists($name) or return;

	$self->hdoc->{module}->{$name}->{changed} = 'no';
	$self->writeHashFile;
}

# returns
# 	- array containing all module names
sub modNames($) {
	my $self = shift;
	my %mods = %{$self->hdoc->{module}};
	return keys(%mods);
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

	foreach (@names) {
		$self->modIsChanged($_) or next;

		push(@mods, $_);

		my @deps = $self->modRevDepends($_);
		foreach (@deps) {
			if (grep(/^$_$/, @mods) == 0) {
				push(@mods, $_);
			}
		}
	}

	foreach (@mods) {
		my $mod = $self->modInstance($_);
		$mod->restartService();
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
		my $classname = $global->hdoc->{module}->{$name}->{class};
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
	my @deps = ();
	my $depsarray = $self->hdoc->{module}->{$name}->{depends};
	defined ($depsarray) or return undef;
	foreach (@{$depsarray}) {
		push(@deps, $_->{module});
	}
	return @deps;
}

# Removes a dependency from the module if both module names exist
# arguments
# 	- string: the name of a module
# 	- string: the name of a module that the first argument depends on
sub removeModDepends($$) {
	my ($self, $name, $depends) = @_;
	# TODO
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

	my $i = -1;
	foreach (@{$self->adoc->{module}}) {
		$i++;
		($_->{name} ne $name) or next;
		delete($self->adoc->{module}[$i]);
		last;
	}
	$self->writeArrayFile;
	return 1;
}

# Adds the tests to the module, if their perl module exists
# arguments
# 	- string: the name of a module
# 	- string: the name of the Perl module that holds the tests
sub addModTest($$$) {
	my ($self, $name, $testmodule) = @_;
	# TODO
}

# returns
#	- a four-dimensional array containing text, location,
#	  order and style in each row.
sub menuEntries($) {
	my $self = shift;
	my @mods = $self->modNames;
	my @array = ();
	foreach (@mods) {
		my $entries = $self->hdoc->{module}->{$_}->{menu};
		defined ($entries) or next;
		foreach (@{$entries}) {
			my @entry = ();
			push(@entry, $_->{text});
			push(@entry, $_->{location});
			push(@entry, $_->{order});
			push(@entry, $_->{style});
			push(@array, \@entry);
		}
	}
	return \@array;
}

# Removed the tests from the module, if they had been previously added
# arguments
# 	- string: the name of a module
# 	- string: the name of the Perl module that holds the tests
sub removeModTest($$$) {
	my ($self, $name, $testmodule) = @_;
	# TODO
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
# 	- integer: the port number on which the admin interface should listen on
sub setAdminPort($$) {
	my ($self, $port) = @_;
	checkPort($port) or
		throw EBox::Exceptions::InvalidData('data' => 'port',
						    'value' => $port);
	$self->adoc->{admin}[0]->{port} = $port;
	$self->writeArrayFile;
}

# returns:
# 	- the port number on which the admin interface is listening
sub adminPort($) {
	my $self = shift;
	return $self->hdoc->{admin}[0]->{port};
}

# arguments
# 	- locale: the locale the interface should use
sub setLocale($$) {
	my ($self, $locale) = @_;
#	do some check
#	checkLocale($locale) or
#		throw EBox::Exceptions::InvalidData('data' => 'locale',
#						    'value' => $locale);
	$self->adoc->{language}[0]->{locale} = $locale;
	$self->writeArrayFile;
}

# returns:
# 	- the port number on which the admin interface is listening
sub locale($) {
	my $self = shift;
	return $self->hdoc->{language}[0]->{locale};
}

1;
