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

package EBox::Module;

use strict;
use warnings;

use File::Copy;
use Proc::ProcessTable;
use EBox;
use EBox::Config;
use EBox::Global;
use EBox::Sudo qw( :all );
use EBox::Exceptions::Internal;
use EBox::Exceptions::Lock;
use EBox::Gettext;
use EBox::FileSystem;
use HTML::Mason;
use File::Temp qw(tempfile);
use Fcntl qw(:flock);
use Error qw(:try);
use Params::Validate qw(validate_pos validate_with SCALAR HASHREF ARRAYREF);

# Method: _create 
#
#   	Base constructor for a module
#
# Parameters:
#
#       name - module's name
#	domain - locale domain
#
# Returns:
#
#       EBox::Module instance
#
# Exceptions:
#
#      	Internal - If no name is provided
sub _create # (name, domain?)
{
	my $class = shift;
	my %opts = @_;
	my $self = {};
	$self->{name} = delete $opts{name};
	$self->{domain} = delete $opts{domain};
	$self->{title} = delete $opts{title};
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

# Method: revokeConfig 
#
#   	Base method to revoke config. It should be overriden by subclasses 
#   	as needed
#
sub revokeConfig
{
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

# Method: _saveConfig 
#
#   	Base method to save configuration. It should be overriden 
#	by subclasses as needed
#
sub _saveConfig
{
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

# Method: _regenConfig
#
#   	Base method to regenerate configuration. It should be overriden
#	by subclasses as needed
#
sub _regenConfig 
{
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

# Method: _restartService
#
#	This method will try to restart the module's service by means of calling
#	_regenConfig
#
sub restartService
{
	my $self = shift;

	$self->_lock();
	my $global = EBox::Global->getInstance();
	my $log = EBox::logger;
	$log->info("Restarting service for module: " . $self->name);
	try {
		$self->_regenConfig('restart' => 1);
	} finally {
		$self->_unlock();
	};
}

# Method: save
#
#	Sets a module as saved. This implies a call to _regenConfig and set 
#	the module as saved and unlock it.
#
sub save
{
	my $self = shift;

	$self->_lock();
	my $global = EBox::Global->getInstance();
	my $log = EBox::logger;
	$log->info("Restarting service for module: " . $self->name);
	$self->_saveConfig();
	try {
		$self->_regenConfig('save' => '1');
	} finally {
		$global->modRestarted($self->name);
		$self->_unlock();
	};
}

# Method: saveConfig
#
#	Save module config, but do not call _regenConfig
#
sub saveConfig
{
	my $self = shift;

	$self->_lock();
	try {
	  my $global = EBox::Global->getInstance();
	  my $log = EBox::logger;
	  $log->info("Restarting service for module: " . $self->name);
	  $self->_saveConfig();
	}
	finally {
	  $self->_unlock();
	};
}

sub _unlock
{
	my $self = shift;
	flock(LOCKFILE, LOCK_UN);
	close(LOCKFILE);
}

sub _lock
{
	my $self = shift;
	my $file = EBox::Config::tmp . "/" . $self->name . ".lock";
	open(LOCKFILE, ">$file") or
		throw EBox::Exceptions::Internal("Cannot open lockfile: $file");
	flock(LOCKFILE, LOCK_EX | LOCK_NB) or
		throw EBox::Exceptions::Lock($self);
}

# Method: _stopService
#
#	This method will try to stop the module's service. It should be 
#	overriden by subclasses as needed
#
sub _stopService
{
	# default empty implementation. It should be overriden by subclasses as
	# needed
}

# Method: stopService
#
#	This is the external interface to call the implementation which lies in
#	_stopService in subclassess
#
#
sub stopService
{
	my $self = shift;

	$self->_lock();
	try {
		$self->_stopService();
	} finally {
		$self->_unlock();
	};
}


# Method: setAsChanged
#
#   Sets the module as changed
#
sub setAsChanged
{
  my ($self) = @_;
  my $name = $self->name;

  my $global = EBox::Global->getInstance();

  return if $global->modIsChanged($name);

  $global->modChange($name);
}



#
# Method: makeBackup
#
#   restores the module state from a backup	
#
# Parameters:
#  dir - directory used for the backup operation
#  (named parameters following)
#  fullBackup - wether we want to do a full restore as opposed a configuration-only restore (default: false)
#  directlyToDisc - wether the backup is written directly to a CD
#
sub makeBackup # (dir, %options) 
{
  my ($self, $dir, %options) = @_;
  defined $dir or throw EBox::Exceptions::InvalidArgument('directory');
  validate_with ( params => [%options],
		  spec =>  { fullBackup     => { default => 0},  
			     directlyToDisc => { default => 0},
			     progress        => {optional => 1},
			   } );

  my $backupDir = $self->_createBackupDir($dir);

  $self->aroundDumpConfig($backupDir);

  if ($self->can('extendedBackup') and $options{fullBackup}) {
    $self->_bootstrapExtendedBackup($backupDir, %options);
  }

}

# Method: backupDir
#
# Parameters:
#    $dir - directory used for the restore/backup operation
#
# Returns: 
#    the path to the directory used by the module to dump or restore his state
# 
sub backupDir
{
  my ($self, $dir) = @_;
  validate_pos(@_, 1, 1);

  # avoid duplicate paths problem
  my $modulePathPart =  '/' . $self->name() . '.bak';
  ($dir) = split $modulePathPart, $dir;

  my $backupDir = $self->_bak_file_from_dir($dir);
  return $backupDir;
}


# Private method: _createBackupDir
#   creates a directory to dump or restore files containig the module state. If there are already a apropiate directory, it simply returns the path of this directory
#   		
#
# Parameters:
#     $dir - directory used for the restore/backup operation
#
# Returns:
#      the path to the directory used by the module to dump or restore his state
#
sub _createBackupDir
{
  my ($self, $dir) = @_;
  validate_pos(@_, 1, 1);

  my $backupDir = $self->backupDir($dir);

  if (! -d $backupDir) {
    EBox::FileSystem::makePrivateDir($backupDir);
  }

  return $backupDir;
}

sub _bootstrapExtendedBackup
{
  my ($self, $dir, %options) = @_;

  # save version
  if ($self->can('version')) {
    $self->_dump_version($dir);
  }

  $self->extendedBackup(dir => $dir, %options);
}


sub _dump_version
{
  my ($self, $dir) = @_;

  my $file = "$dir/version";
  my $versionInfo = $self->version();

  open my $FH, ">$file" or throw EBox::Exceptions::Internal('Cannot create version backup file');
  print $FH $versionInfo;
  close $FH;
}

#
# Method: restoreBackup
#
#   restores the module state from a backup	
#
# Parameters:
#  dir - directory used for the restore operation 
#  (named parameters following)
#  fullRestore - wether we want to do a full restore as opposed a configuration-only restore (default: false)
#
sub restoreBackup # (dir, %options) 
{
  my ($self, $dir, %options) = @_;
  defined $dir or throw EBox::Exceptions::InvalidArgument('directory');
  validate_with ( params => [%options],
		  spec =>  { fullRestore => { default => 0}   } );
  
  my $backupDir = $self->backupDir($dir);
  (-d $backupDir) or throw EBox::Exceptions::Internal("$backupDir must be a directory");

  $self->aroundRestoreConfig($backupDir);

  if ($options{fullRestore} and $self->can('extendedRestore')) {
    $self->_bootstrapExtendedRestore($backupDir, %options);
  }
}

sub _bootstrapExtendedRestore
{
  my ($self, $dir, @options) = @_;

  my $version = $self->_read_version($dir);
  $self->extendedRestore(dir => $dir, version => $version, @options);
}

sub _read_version
{
  my ($self, $dir) = @_;
  my $file = "$dir/version";

  return undef if (! -f $file);
  
  open my $FH, "<$file" or throw EBox::Exceptions::Internal("Version info file cannot be opened");
  my @versionInfo = <$FH>;
  close $FH;

  my $versionInfo = join "\n", @versionInfo;
  return $versionInfo
}


sub _bak_file_from_dir
{
  my ($self, $dir) = @_;
  $dir =~ s{/+$}{};
  my $file = "$dir/" . $self->name . ".bak";
  return $file;
}

#
# Method: restoreDependencies
#
#   this method should be override by any module that depends on another module/s  to be restored from a backup 
#
# Returns:
#	a reference to a list with the names of required eBox modules for a sucesful restore. (default: none)
#
# 
sub restoreDependencies
{
  my ($self) = @_;
  return [];
}



# Method:  dumpConfig
#
#   this must be override by individuals to restore to dump the
#   configuration properly
#
# Parameters:
#   dir - directory where the modules backup files are
#         dumped (without trailing slash)
#
sub dumpConfig
{
  my ($self, $dir) = @_;
  validate_pos(@_, 1, 1);
}




#
# Method: aroundDumpConfig
#
# Wraps the dumpConfig call; the purpose of this sub is to allow
# specila types of modules (GConfModule p.e) to call another method
# alongside with dumConfig transparently.
#
# Normally, ebox modules does not need to override this
#
# Parameters:
#   dir - Directoy where the module configuration is been dumped
#
sub aroundDumpConfig
{
  my ($self, $dir) = @_;
  validate_pos(@_, 1, 1);

  $self->dumpConfig($dir);
}



#
# Method:  restoreConfig
#
#   This must be override by individuals to restore its configuration
#   from the backup file. Those files are the same were created with
#   dumpConfig
#
# Parameters: 
#  dir - Directory where are located the backup files
#        (without the trailing slash)
#
sub restoreConfig
{
  my ($self, $dir) = @_;
  validate_pos(@_, 1, 1);
}


#  Method: aroundRestoreConfig
#
# wraps the restoreConfig call; the purpose of this sub is to allow specila
# types of modules (GConfModule p.e) to call another method alongside with
# restoreConfig transparently 
# normally ebox modules does not need to override this
#
# Parameters:
#  dir - directory where are located the backup files
#
sub aroundRestoreConfig
{
  my ($self, $dir) = @_;
  validate_pos(@_, 1, 1);

  $self->restoreConfig($dir);
}



# Method: initChangedState
#
#    called before module is in the changed state. 
sub initChangedState
{
  my ($self) = @_;

   my $global = EBox::Global->getInstance();
   $global->modIsChanged($self->name) and 
     throw EBox::Exceptions::Internal($self->name . ' module already has changed state');


}

#
# Method: name 
#
#	Returns the module name of the current module instance   
#
# Returns:
#
#      	strings - name 
#
sub name
{
	my $self = shift;
	return $self->{name};
}

#
# Method: setName 
#
#	Sets the module name for the current module instance
#
# Parameters:
#
#      	name - module name
#
sub setName # (name) 
{
	my $self = shift;
	my $name = shift;
	$self->{name} = $name;
}

#
# Method: title
#
#	Returns the module title of the current module instance   
#
# Returns:
#
#      	string - title or name if title was not provided
#
sub title
{
	my ($self) = @_;
	if(defined($self->{title})) {
		return $self->{title};
	} else {
		return $self->{name};
	}
}

#
# Method: setTitle
#
#	Sets the module title for the current module instance
#
# Parameters:
#
#      	title - module title
#
sub setTitle # (title) 
{
	my ($self,$title) = @_;
	$self->{title} = $title;
}

#
# Method: actionMessage
#
#	Gets the action message for an action
#
# Parameters:
#
# 	action - action name
sub actionMessage
{
	my ($self,$action) = @_;
	if(defined($self->{'actions'})) {
		return $self->{'actions'}->{$action};
	} else {
		return $action;
	}
}

#
# Method: menu 
#
#	This method returns the menu for the module. What it returns 
#	it will be added up to the interface's menu. It should be 
#	overriden by subclasses as needed
sub menu
{
	# default empty implementation
	return undef;
}

#
# Method: summary
#
#	Return the summary for the module. What it returns will
#	be added up to the common summary page. It should be overriden by 
#	subclasses as needed
#
# Returns:
#
#       <EBox::Summary::Module> - the summary for the module
#
sub summary
{
	# default empty implementation
	return undef;
}

#
# Method: statusSummary
#
#	Return the status summary for the module. What it returns will
#	be added up to the common status summary page. It should be overriden by
#	subclasses as needed.
#
# Returns:
#
#       <EBox::Summary::Status> - the summary status for the module
#
sub statusSummary
{
	# default empty implementation
	return undef;
}

#
# Method: domain 
#
#	Returns the locale domain for the current module instance 
#
# Returns:
#
#      	strings - locale domain
#
sub domain
{
	my $self = shift;

	if (defined $self->{domain}){
		return $self->{domain};
	} else {
		return 'ebox';
	}
}

# Method: package 
#
#	Returns the package name 
#
# Returns:
#
#      	strings - package name 
#
# TODO Change domain  for package which
# is more general. But we must ensure no module uses it directly
sub package
{
	my $self = shift;

	return $self->domain();
}

#
# Method: pidRunning 
#
#	Checks if a PID is running
#
# Parameters:
#	
#	pid - PID number 
#
# Returns:
#
#	boolean - True if it's running , otherise false
sub pidRunning
{
	my ($self, $pid) = @_;
	my $t = new Proc::ProcessTable;
	foreach my $proc (@{$t->table}) {
		($pid eq $proc->pid) and return 1;
	}
	return undef;
}

#
# Method: pidFileRunning 
#
#	Given a file holding a PID, it gathers it and checks if it's running
#
# Parameters:
#	
#	file - file name
#
# Returns:
#
#	boolean - True if it's running , otherise false
#
sub pidFileRunning
{
	my ($self, $file) = @_;
	(-f $file) or return undef;
	open(PIDF, $file) or return undef;
	my $pid = <PIDF>;
	chomp($pid);
	close(PIDF);
	defined($pid) or return undef;
	($pid ne "") or return undef;
	return $self->pidRunning($pid);
}

#
# Method: writeConfFile 
#
#	It executes a given mason component with the passed parameters over 
#	a file. It becomes handy to set configuration files for services. 
#	Also, its file permissions will be kept.
#       It can be called as class method. (XXX: this design or is an implementation accident?)
#      XXX : the correct behaviour will be to throw exceptions if file will not be stated and no defaults are provided. It will provide hardcored defaults instead because we need to be backwards-compatible
#
#
# Parameters:
#
#	file - file name which will be overwritten with the execution output
#	component - mason component
#	params - parameters for the mason component. Optional. Defaults to no parameters
#       defaults - a reference to hash with keys mode, uid and gid. Those values will be used when creating a new file. (If the file already exists the existent values of these parameters will be left untouched)
#
# Returns:
#
#	boolean - True if it's running , false otherwise
#
sub writeConfFile # (file, component, params, defaults)
{
	my ($self, $file, $compname, $params, $defaults) = @_;
	validate_pos(@_, 1, { type =>  SCALAR }, { type => SCALAR }, { type => ARRAYREF, default => [] }, { type => HASHREF, optional => 1 });

	my ($fh,$tmpfile) = tempfile(DIR => EBox::Config::tmp);
	unless($fh) {
		throw EBox::Exceptions::Internal(
			"Could not create temp file in " . EBox::Config::tmp);
	}
	my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::stubs,
		out_method => sub { $fh->print($_[0]) });
	my $comp = $interp->make_component(comp_file =>
		EBox::Config::stubs . "/" . $compname);
	$interp->exec($comp, @{$params});
	$fh->close();

	my $mode;
	my $uid;
	my $gid;
	if((not defined($defaults)) and (my $st = stat($file))) {
	    $mode= sprintf("%04o", $st->mode & 07777); 
	    $uid = $st->uid;
	    $gid = $st->gid;

	} else {
	    defined $defaults or $defaults = {};
	    $mode = exists $defaults->{mode} ?  $defaults->{mode}  : '0644';
	    $uid  = exists $defaults->{uid}  ?  $defaults->{uid}   : 0;
	    $gid  = exists $defaults->{gid}  ?  $defaults->{gid}   : 0;
	}

	EBox::Sudo::root("/bin/mv $tmpfile  $file");
	EBox::Sudo::root("/bin/chmod $mode $file");
	EBox::Sudo::root("/bin/chown $uid.$gid $file");
}



1;
