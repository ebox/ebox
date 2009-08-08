package EBox::Module;

use strict;
use warnings;

use XML::Simple;
use XML::XPath;
use XML::XPath::XMLParser;
use File::Copy;
use EBox::Config;
use EBox::Global;
use EBox::Schema;
use EBox::Exceptions::Internal;

## options:
##		name [required]
sub _create {
	my $class = shift;
	my %opts = @_;
	my $self = {};
	$self->{name} = delete $opts{name};
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

sub restartService($) {
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

sub stopService($) {
	# default empty implementation. It should be overriden by subclasses as
	# needed
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

1;
