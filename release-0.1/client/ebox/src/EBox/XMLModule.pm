package EBox::XMLModule;

use strict;
use warnings;

use base 'EBox::Module';

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
	my $keyattr = delete $opts{keyattr} ;

	my $self =$class->SUPER::_create(@_);

	$self->{file} = EBox::Config::conf . '/' . $self->{name} . ".xml";
	$self->{keyattr} = $keyattr;
	if (defined($self->{keyattr})) {
		$self->{hxs} = new XML::Simple(ForceArray => 1,
					       KeyAttr => $self->{keyattr});
	} else {
		$self->{hxs} = new XML::Simple(ForceArray => 1);
	}
	$self->{axs} = new XML::Simple(ForceArray => 1, KeyAttr => "");
	$self->{hdoc} = undef;
	$self->{adoc} = undef;
	$self->{xpdoc} = undef;
	bless($self, $class);
	return $self;
}

sub revokeConfig($) {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	$global->modRestarted($self->name);
	$self->{hdoc} = undef;
	$self->{xpdoc} = undef;
	$self->{adoc} = undef;
}

sub _saveConfig($) {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	if ($global->modIsChanged($self->name)) {
		if ($self->_newfilename ne $self->filename) {
			copy($self->_newfilename, $self->filename);
		}
	}
}

sub _regenConfig {
}

sub restartService($) {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	my $log = EBox::Global->logger;
	$log->debug("Restarting service for module: " . $self->name);
	$self->_saveConfig;
	$self->_regenConfig;
	$global->modRestarted($self->name);
}

sub writeHashFile($) {
	my $self = shift;

	defined($self->{hdoc}) or return;
	$self->_writeFile($self->{hdoc}, $self->{hxs});
	$self->{adoc} = undef;
}

sub writeArrayFile($) {
	my $self = shift;

	defined($self->{adoc}) or return;
	$self->_writeFile($self->{adoc}, $self->{axs});
	$self->{hdoc} = undef;
}

sub _writeFile($$$) {
	my $self = shift;
	my $xml = shift;
	my $xs = shift;
	my $global = EBox::Global->modInstance('global');

	my $filename = $self->_newfilename;
	my $savefile = $filename . ".tmp";
	open(my $fh, ">", $savefile) or
		throw EBox::Exceptions::Internal("Could not open $savefile");
	$xs->XMLout($xml, AttrIndent => 1, XMLDecl => 1,
			RootName => $self->name, OutputFile => $fh);
	close($fh);
	$global->modChange($self->name);

	if (EBox::Schema::validate($filename)) {
		copy($savefile, $filename) or
			throw EBox::Exceptions::Internal(
				"Could not write $filename");
		unlink($savefile);
	} else {
		throw EBox::Exceptions::Internal("Module ". $self->name .
			" wrote invalid configuration in ".  $savefile);
	}
}

sub adoc {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	my $filename;
	if ($global->modIsChanged($self->name)) {
		$filename = $self->_newfilename;
	} else {
		$filename = $self->filename;
	}
	unless (defined($self->{adoc})) {
		$self->{adoc} = $self->{axs}->XMLin($filename);
	}
	return $self->{adoc};
}

sub hdoc {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	my $filename;
	if ($global->modIsChanged($self->name)) {
		$filename = $self->_newfilename;
	} else {
		$filename = $self->filename;
	}
	unless (defined($self->{hdoc})) {
		$self->{hdoc} = $self->{hxs}->XMLin($filename);
	}
	return $self->{hdoc};
}

sub xpdoc {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	my $filename;
	if ($global->modIsChanged($self->name)) {
		$filename = $self->_newfilename;
	} else {
		$filename = $self->filename;
	}
	unless (defined($self->{xpdoc})) {
		$self->{xpdoc} = XML::XPath->new(filename => $filename);
	}
	return $self->{xpdoc};
}

sub filename {
	my $self = shift;
	return $self->{file};
}

sub _newfilename {
	my $self = shift;
	return $self->{file} . ".new";
}

sub setFileName {
	my $self = shift;
	my $name = shift;
	return unless defined $name;
	$self->{file} = $name;
}

sub setKeyAttr {
	my $self = shift;
	my $keyattr = shift;
	$self->{keyattr} = $keyattr;
}

1;
