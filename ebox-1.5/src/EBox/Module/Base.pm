# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
# Copyright (C) 2006-2008 Warp Networks S.L.
# Copyright (C) 2009 eBox Technologies S.L.
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

package EBox::Module::Base;

use strict;
use warnings;

use File::Copy;
use Proc::ProcessTable;
use EBox;
use EBox::Util::Lock;
use EBox::Config;
use EBox::Global;
use EBox::Sudo qw( :all );
use EBox::Exceptions::Internal;
use EBox::Exceptions::Lock;
use EBox::Gettext;
use EBox::FileSystem;
use EBox::ServiceManager;
use EBox::DBEngineFactory;
use HTML::Mason;
use File::Temp qw(tempfile);
use Fcntl qw(:flock);
use Error qw(:try);

# Method: _create
#
#   Base constructor for a module
#
# Parameters:
#
#   name - String module's name
#   domain - String locale domain
#   printableName - String printable module's name
#   title - String the module's title
#
# Returns:
#
#   EBox::Module instance
#
# Exceptions:
#
#   Internal - If no name is provided
sub _create # (name, domain?)
{
    my $class = shift;
    my %opts = @_;
    my $self = {};
    $self->{name} = delete $opts{name};
    $self->{domain} = delete $opts{domain};
    $self->{title} = delete $opts{title};
    my $domain = settextdomain($self->{domain});
    $self->{printableName} = __(delete $opts{printableName});
    settextdomain($domain);
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

# Method: info
#
#   Read module information from YAML file
#
sub info
{
    my ($self) = @_;
    return EBox::Global::readModInfo($self->{name});
}

# Method: depends
#
#       Return an array ref with the names of the modules that this
#       module depends on
#
# Returns:
#
#       array ref - holding the names of the modules that the requested module
#
sub depends
{
    my ($self) = @_;

    my $info = $self->info();
    my @list = map {s/^\s+//; $_} @{$info->{'depends'}};
    if (@list) {
        return \@list;
    } else {
        return [];
    }
}


# Method: revokeConfig
#
#       Base method to revoke config. It just notifies that he module has been
#       restarted.
#       It should be overriden by subclasses as needed
#
sub revokeConfig
{
    my $self = shift;
    my $global = EBox::Global->getInstance();

    $global->modIsChanged($self->name) or return;
    $global->modRestarted($self->name);
}

# Method: _saveConfig
#
#   Base method to save configuration. It should be overriden
#   by subclasses as needed
#
sub _saveConfig
{
    # default empty implementation. It should be overriden by subclasses as
    # needed
}

# Method: save
#
#   Sets a module as saved. This implies a call to _regenConfig and set
#   the module as saved and unlock it.
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
        $self->_regenConfig();
    } finally {
        $global->modRestarted($self->name);
        $self->_unlock();
    };
}

# Method: saveConfig
#
#   Save module config, but do not call _regenConfig
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

# Method: saveConfigRecursive
#
#   Save module config and the modules which depends on recursively
#
sub saveConfigRecursive
{
    my ($self) = @_;

    $self->_saveConfigRecursive($self->name);
}

# Method: _saveConfigRecursive
#
#   Save module config and the modules which depends on recursively
#
sub _saveConfigRecursive
{
    my ($self, $module) = @_;

    my $global = EBox::Global->getInstance();
    for my $dependency (@{$global->modDepends($module)}) {
        $self->_saveConfigRecursive($dependency);
    }

    my $modInstance = EBox::Global->modInstance($module);
    $modInstance->saveConfig();
    $global->modRestarted($module);
}

sub _unlock
{
    my ($self) = @_;
    EBox::Util::Lock::unlock($self->name);
}

sub _lock
{
    my ($self) = @_;
    EBox::Util::Lock::lock($self->name);
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
# bug - wether we are making a bug report instead of a normal backup
sub makeBackup # (dir, %options)
{
  my ($self, $dir, %options) = @_;
  defined $dir or throw EBox::Exceptions::InvalidArgument('directory');

  my $backupDir = $self->_createBackupDir($dir);

  $self->aroundDumpConfig($backupDir, %options);

  if ($options{fullBackup}) {
    $self->extendedBackup(dir => $backupDir, %options);
  }

}


# default implementation: do nothing
sub extendedBackup
{
  # my %params = @_;
  # my $dir = $params{dir};
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

  my $backupDir = $self->backupDir($dir);

  if (! -d $backupDir) {
    EBox::FileSystem::makePrivateDir($backupDir);
  }

  return $backupDir;
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

  my $backupDir = $self->backupDir($dir);
  (-d $backupDir) or throw EBox::Exceptions::Internal("$backupDir must be a directory");

  if (not $options{dataRestore}) {
    $self->aroundRestoreConfig($backupDir);
  }


  if ($options{fullRestore} or $options{dataRestore}) {
    $self->extendedRestore(dir => $backupDir, %options);
  }
}


# default implementation: do nothing
sub extendedRestore
{
  # my %params = @_;
  # my $dir = $params{dir};
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
#   a reference to a list with the names of required eBox modules for a sucesful restore. (default: none)
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
  my ($self, $dir, %options) = @_;

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
  my ($self, $dir, @options) = @_;


  $self->dumpConfig($dir, @options);
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
#   Return the module name of the current module instance
#
# Returns:
#
#       strings - name
#
sub name
{
    my $self = shift;
    return $self->{name};
}

#
# Method: setName
#
#   Set the module name for the current module instance
#
# Parameters:
#
#   name - module name
#
sub setName # (name)
{
    my $self = shift;
    my $name = shift;
    $self->{name} = $name;
}

# Method: printableName
#
#       Return the printable module name of the current module
#       instance
#
# Returns:
#
#       String - the printable name
#
sub printableName
{

    my ($self) = @_;

    if ( $self->{printableName} ) {
        return $self->{printableName};
    } else {
        return $self->name();
    }

}

# Method: setPrintableName
#
#       Set the printable module name of the current module
#       instance
#
# Parameters:
#
#       printableName - String the printable name
#
sub setPrintableName
{

    my ($self, $printableName) = @_;

    $self->{printableName} = $printableName;

}


#
# Method: title
#
#   Returns the module title of the current module instance
#
# Returns:
#
#   string - title or name if title was not provided
#
sub title
{
    my ($self) = @_;
    if(defined($self->{title})) {
        return $self->{title};
    } elsif ( $self->{printableName} ) {
        return $self->{printableName};
    } else {
        return $self->{name};
    }
}

#
# Method: setTitle
#
#   Sets the module title for the current module instance
#
# Parameters:
#
#   title - module title
#
sub setTitle # (title)
{
    my ($self,$title) = @_;
    $self->{title} = $title;
}

#
# Method: actionMessage
#
#   Gets the action message for an action
#
# Parameters:
#
#   action - action name
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
#   This method returns the menu for the module. What it returns
#   it will be added up to the interface's menu. It should be
#   overriden by subclasses as needed
sub menu
{
    # default empty implementation
    return undef;
}

#
# Method: widgets
#
#   Return the widget names for the module. It should be overriden by
#   subclasses as needed
#
# Returns:
#
#   An array of hashes containing keys 'title' and 'widget', 'title' being the
#   title of the widget and 'widget' a function that can fill an
#   EBox::Dashboard::Widget that will be passed as a parameter
#
#   It can optionally have the key 'default' set to 1 to have the widget
#   added by default to the dashboard the first time it's seen.
#
#   It can also contain a 'parameter' key which will be passed as parameter to
#   the widget function. This is intended to allow the dynamic creation of
#   several widgets.
#
sub widgets
{
    # default empty implementation
    return {};
}

#
# Method: widget
#
#   Return the appropriate widget if exists or undef otherwise
#
# Parameters:
#       name - the widget name
#
# Returns:
#
#       <EBox::Dashboard::Widget> with the appropriate widget
#
sub widget
{
    my ($self, $name) = @_;
    my $widgets = $self->widgets();
    my $winfo = $widgets->{$name};
    if(defined($winfo)) {
        my $widget = new EBox::Dashboard::Widget($winfo->{'title'},$self->{'name'},$name);
        #fill the widget
        $widget->{'module'} = $self->{'name'};
        $widget->{'default'} = $winfo->{'default'};
        my $wfunc = $winfo->{'widget'};
        &$wfunc($self, $widget, $winfo->{'parameter'});
        return $widget;
    } else {
        return undef;
    }
}

#
# Method: statusSummary
#
#   Return the status summary for the module. What it returns will
#   be added up to the common status summary page. It should be overriden by
#   subclasses as needed.
#
# Returns:
#
#       <EBox::Dashboard::ModuleStatus> - the summary status for the module
#
sub statusSummary
{
    # default empty implementation
    return undef;
}

#
# Method: domain
#
#   Returns the locale domain for the current module instance
#
# Returns:
#
#   strings - locale domain
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
#   Returns the package name
#
# Returns:
#
#   strings - package name
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
#   Checks if a PID is running
#
# Parameters:
#
#   pid - PID number
#
# Returns:
#
#   boolean - True if it's running , otherise false
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
#   Given a file holding a PID, it gathers it and checks if it's running
#
# Parameters:
#
#   file - file name
#
# Returns:
#
#   boolean - True if it's running , otherise false
#
sub pidFileRunning
{
    my ($self, $file) = @_;
    my $pid;
    try {
        my $output = EBox::Sudo::root("cat $file");
        ($pid) = @{$output}[0] =~ m/(\d+)/;
    } otherwise {
        return undef;
    };
    defined($pid) or return undef;
    ($pid ne "") or return undef;
    return $self->pidRunning($pid);
}

# Method: _preSetConf
#
#   Base method which is called before _setConf. It should be overriden
#   by subclasses if you need something to be done before _setConf is run
#
sub _preSetConf
{
    # default empty implementation. It should be overriden by subclasses as
    # needed
}

sub _hook
{
    my ($self, $type, @params) = @_;

    my $hookfile = EBox::Config::etc() . "hooks/" . $self->{'name'} . "." . $type;
    if (-x "$hookfile") {
        my $log = EBox::logger;
        my $command = $hookfile . " " . join(" ", @params);
        $log->info("Running hook: " . $command);

        EBox::Sudo::root("$command");
    }
}

sub _preSetConfHook
{
    my ($self) = @_;
    $self->_hook('presetconf');
}

sub _postSetConfHook
{
    my ($self) = @_;
    $self->_hook('postsetconf');
}

# Method: _setConf
#
#   Base method to write the configuration. It should be overriden
#   by subclasses as needed
#
sub _setConf
{
    # default empty implementation. It should be overriden by subclasses as
    # needed
}

# Method: _regenConfig
#
#   Base method to regenerate configuration. It should be overriden
#   by subclasses as needed
#
sub _regenConfig
{
    my ($self) = @_;

    my @params = (@_);
    shift(@params);

    $self->_preSetConf(@params);
    $self->_preSetConfHook();
    $self->_setConf(@params);
    $self->_postSetConfHook();
}

# Method: writeConfFileNoCheck
#
#    It executes a given mason component with the passed parameters over
#    a file. It becomes handy to set configuration files for services.
#    Also, its file permissions will be kept.
#    It is called as class method.
#    XXX : the correct behaviour will be to throw exceptions if file will not be stated and no defaults are provided. It will provide hardcored defaults instead because we need to be backwards-compatible
#
#
# Parameters:
#
#    file      - file name which will be overwritten with the execution output
#    component - mason component
#    params    - parameters for the mason component. Optional. Defaults to no parameters
#    defaults  - a reference to hash with keys mode, uid and gid. Those values will be used when creating a new file. (If the file already exists the existent values of these parameters will be left untouched)
#
sub writeConfFileNoCheck # (file, component, params, defaults)
{
    my ($file, $compname, $params, $defaults) = @_;

    my $oldUmask = umask 0007;
    my ($fh,$tmpfile);
    try {
        ($fh,$tmpfile) = tempfile(DIR => EBox::Config::tmp);
        unless($fh) {
            throw EBox::Exceptions::Internal(
                                             "Could not create temp file in " . EBox::Config::tmp);
        }
    }
    finally {
        umask $oldUmask;
    };

    my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::stubs,
                                          out_method => sub { $fh->print($_[0]) });
    my $comp;

    try {
        $comp = $interp->make_component(comp_file =>
                                         EBox::Config::stubs . "/" . $compname);
    } otherwise {
        my $ex = shift;
        throw EBox::Exceptions::Internal("Template $compname failed with $ex");
    };

    # Workaround bogus mason warnings, redirect stderr to /dev/null to not
    # scare users. New mason version fixes this issue
    my $old_stderr;
    my $tmpErr = EBox::Config::tmp() . 'mason.err';
    open($old_stderr,">&STDERR");
    open(STDERR,">$tmpErr");

    $interp->exec($comp, @{$params});
    $fh->close();

    open(STDERR,">&$old_stderr");

    my $mode;
    my $uid;
    my $gid;
    if ((not defined($defaults)) and (my $st = stat($file))) {
        $mode= sprintf("%04o", $st->mode & 07777);
        $uid = $st->uid;
        $gid = $st->gid;

    } else {
        defined $defaults or $defaults = {};
        $mode = exists $defaults->{mode} ?  $defaults->{mode}  : '0644';
        $uid  = exists $defaults->{uid}  ?  $defaults->{uid}   : 0;
        $gid  = exists $defaults->{gid}  ?  $defaults->{gid}   : 0;
    }

    EBox::Sudo::root("/bin/mv $tmpfile  '$file'");
    EBox::Sudo::root("/bin/chmod $mode '$file'");
    EBox::Sudo::root("/bin/chown $uid.$gid '$file'");
}

# Method: writeFile
#
#    Writes a file with the given data, owner and permissions.
#
# Parameters:
#
#    file      - file name which will be overwritten with the execution output
#    data      - data to write in the file
#    defaults  - a reference to hash with keys mode, uid and gid. Those values will be used when creating a new file. (If the file already exists the existent values of these parameters will be left untouched)
#
sub writeFile # (file, data, defaults)
{
    my ($file, $data, $defaults) = @_;

    my $oldUmask = umask 0007;
    my ($fh,$tmpfile);
    try {
        ($fh,$tmpfile) = tempfile(DIR => EBox::Config::tmp);
        unless($fh) {
            throw EBox::Exceptions::Internal(
                                             "Could not create temp file in " . EBox::Config::tmp);
        }
    }
    finally {
        umask $oldUmask;
    };

    $fh->print($data);
    $fh->close();

    my $mode;
    my $uid;
    my $gid;
    if ((not defined($defaults)) and (my $st = stat($file))) {
        $mode= sprintf("%04o", $st->mode & 07777);
        $uid = $st->uid;
        $gid = $st->gid;

    } else {
        defined $defaults or $defaults = {};
        $mode = exists $defaults->{mode} ?  $defaults->{mode}  : '0644';
        $uid  = exists $defaults->{uid}  ?  $defaults->{uid}   : 0;
        $gid  = exists $defaults->{gid}  ?  $defaults->{gid}   : 0;
    }

    EBox::Sudo::root("/bin/mv $tmpfile  '$file'");
    EBox::Sudo::root("/bin/chmod $mode '$file'");
    EBox::Sudo::root("/bin/chown $uid.$gid '$file'");
}

# Method: report
#
#   returns the reporting information provided by the module
#
#   Returns:
#     hash reference with the report information
#
#     If not overriden by the subclasses it will return undef
sub report
{
    my ($self) = @_;
    return undef;
}

# Method: runMontlyQuery
#
#   Runs a query in the database for all the months in t erange,
#   organizing the data for its use in the report
#
# Parameters:
#
#       beg - initial year-month (i.e., '2009-10')
#	    end - final year-month
#       query - SQL query without any dates
#       options - hash containing options for the processing of the results
#          key - if key is provided, multiple rows will be processed and
#                hashed by the content of the key field
#
#   Returns:
#     hash reference with the report information
#
#     If not overriden by the subclasses it will return undef
sub runMonthlyQuery
{
    my ($self, $beg, $end, $query, $options) = @_;

    defined($options) or $options = {};

    my $data = {};
    my $db = EBox::DBEngineFactory::DBEngine();

    my ($begyear, $begmonth) = split('-', $beg);
    my ($endyear, $endmonth) = split('-', $end);

    my $year = $begyear;
    my $month = $begmonth;

    my $orig_where = $query->{'where'};

    my $skipped = 0;

    my $key = $options->{'key'};

    while (
        ($year < $endyear) or
        (($year == $endyear) and ($month <= $endmonth))
    ) {
        my $date_where = "date >= '$year-$month-01 00:00:00' AND " .
            "date < date '$year-$month-01 00:00:00' + interval '1 month'";
        my $new_where;
        if (defined($orig_where)) {
            $new_where = "$orig_where AND $date_where";
        } else {
            $new_where = "$date_where";
        }
        $query->{'where'} = $new_where;

        my $results = $db->query_hash($query);
        if (@{$results}) {
            my @fields = keys(%{@{$results}[0]});
            if (defined($key)) {
                for my $r (@{$results}) {
                    my $keyname = $r->{$key};
                    if (not exists($data->{$keyname})) {
                        $data->{$keyname} = {};
                    }
                    for my $f (@fields) {
                        if ($f eq $key) {
                            next;
                        }
                        if (not exists($data->{$keyname}->{$f})) {
                            $data->{$keyname}->{$f} = [];
                        }
                        my $empties = $skipped;
                        while($empties > 0) {
                            push(@{$data->{$keyname}->{$f}}, 0);
                            $empties--;
                        }
                        push(@{$data->{$keyname}->{$f}}, $r->{$f});
                    }
                }
            } else {
                for my $r (@{$results}) {
                    for my $f (@fields) {
                        if (not exists($data->{$f})) {
                            $data->{$f} = [];
                        }
                        my $empties = $skipped;
                        while($empties > 0) {
                            push(@{$data->{$f}}, 0);
                            $empties--;
                        }
                        push(@{$data->{$f}}, $r->{$f});
                    }
                }
            }
            $skipped = 0;
        } else {
            $skipped++;
        }
        if($month == 12) {
            $month = 1;
            $year++;
        } else {
            $month++;
        }
    }
    return $data;
}

sub runQuery
{
    my ($self, $beg, $end, $query) = @_;

    my $data = {};
    my $db = EBox::DBEngineFactory::DBEngine();

    my ($begyear, $begmonth) = split('-', $beg);
    my ($endyear, $endmonth) = split('-', $end);

    my $orig_where = $query->{'where'};
    my $date_where = "date >= '$begyear-$begmonth-01 00:00:00' AND " .
                "date < date '$endyear-$endmonth-01 00:00:00' + interval '1 month'";
    my $new_where;
    if (defined($orig_where)) {
        $new_where = "$orig_where AND $date_where";
    } else {
        $new_where = "$date_where";
    }
    $query->{'where'} = $new_where;

    my $results = $db->query_hash($query);
    if (@{$results}) {
        my @fields = keys(%{@{$results}[0]});

        for my $f (@fields) {
            $data->{$f} = [];
        }

        for my $r (@{$results}) {
            for my $f (@fields) {
                push(@{$data->{$f}}, $r->{$f});
            }
        }
        return $data;
    }
    return undef;
}

sub runCompositeQuery
{
    my ($self, $beg, $end, $query, $key, $next_query) = @_;

    my $data = {};
    my $db = EBox::DBEngineFactory::DBEngine();

    my ($begyear, $begmonth) = split('-', $beg);
    my ($endyear, $endmonth) = split('-', $end);

    my $orig_where = $query->{'where'};
    my $date_where = "date >= '$begyear-$begmonth-01 00:00:00' AND " .
                "date < date '$endyear-$endmonth-01 00:00:00' + interval '1 month'";
    my $new_where;
    if (defined($orig_where)) {
        $new_where = "$orig_where AND $date_where";
    } else {
        $new_where = "$date_where";
    }
    $query->{'where'} = $new_where;

    my $results = $db->query_hash($query);
    my @keys = map { $_->{$key} } @{$results};
    (@keys) or return undef;

    $orig_where = $next_query->{'where'};
    for my $k (@keys) {
        $data->{$k} = {};
        my $date_where = "date >= '$begyear-$begmonth-01 00:00:00' AND " .
                    "date < date '$endyear-$endmonth-01 00:00:00' + interval '1 month'";
        my $new_where;
        if (defined($orig_where)) {
            $new_where = "$orig_where AND $date_where";
        } else {
            $new_where = "$date_where";
        }
        my $regex = '_' . $key . '_';
        $new_where =~ s/$regex/$k/;
        $next_query->{'where'} = $new_where;

        $results = $db->query_hash($next_query);
        if (@{$results}) {
            my @fields = keys(%{@{$results}[0]});

            for my $f (@fields) {
                $data->{$k}->{$f} = [];
            }

            for my $r (@{$results}) {
                for my $f (@fields) {
                    push(@{$data->{$k}->{$f}}, $r->{$f});
                }
            }
        }
    }
    return $data;
}


sub consolidateReportFromLogs
{
    my ($self) = @_;

    my $db = EBox::DBEngineFactory::DBEngine();

    my $queries = $self->consolidateReportQueries();

    for my $q (@{$queries}) {
        my $target_table = $q->{'target_table'};
        my $query = $q->{'query'};

        my $res = $db->query_hash({
            'select' => 'EXTRACT(EPOCH FROM last_date) AS date',
            'from' => 'report_consolidation',
            'where' => "report_table = '$target_table'"
        });

        my $date;
        if(@{$res}) {
            my $row = shift(@{$res});
            $date = $row->{'date'};
        } else {
            $res = $db->query_hash({
                'select' => 'EXTRACT(EPOCH FROM timestamp) AS date',
                'from' => $query->{'from'},
                'order' => "timestamp",
                'limit' => 1
            });
            my $row = shift(@{$res});

            #if there are no rows at all, just continue
            defined($row) or next;

            #substract one so we can run the query with > and still get this
            #result in
            $date = $row->{'date'} - 1;

            #later we call update so we need to have something inserted
            $db->insert('report_consolidation', {
                'report_table' => $target_table,
                'last_date' => 'epoch'
            });
        }
        my @time = localtime($date);
        my $year = $time[5]+1900;
        my $month = $time[4]+1;

        my @curtime = localtime();
        my $curyear = $curtime[5]+1900;
        my $curmonth = $curtime[4]+1;

        my $orig_where = $query->{'where'};

        while (
            ($year < $curyear) or
            (($year == $curyear) and ($month <= $curmonth))
        ) {
            my $date_where = "timestamp > (timestamp with time zone 'epoch' + $date * interval '1 second') AND timestamp >= '$year-$month-01 00:00:00' AND " .
                "timestamp < date '$year-$month-01 00:00:00' + interval '1 month'";
            my $time_res = $db->query_hash({
                'select' => 'EXTRACT(EPOCH FROM timestamp) AS date',
                'from' => $query->{'from'},
                'where' => $date_where,
                'order' => 'date DESC',
                'limit' => 1
            });
            my $time_row = shift(@{$time_res});
            my $last_time = $time_row->{'date'};

            if (defined($last_time)) {
                $date_where = "timestamp > (timestamp with time zone 'epoch' + $date * interval '1 second') AND timestamp >= '$year-$month-01 00:00:00' AND " .
                    "timestamp <= timestamp with time zone 'epoch' + $last_time * interval '1 second'";
                my $new_where;
                if (defined($orig_where)) {
                    $new_where = "$orig_where AND $date_where";
                } else {
                    $new_where = "$date_where";
                }
                $query->{'where'} = $new_where;

                my $results = $db->query_hash($query);
                if (@{$results}) {
                    my @fields = keys(%{@{$results}[0]});
                    my @groupFields = split(/ *, */,$query->{'group'});
                    for my $r (@{$results}) {
                        my @where;
                        for my $f (@groupFields) {
                            push(@where, $f . " = '" . $r->{$f} . "'");
                        }
                        push(@where, "date = '$year-$month-01'");
                        my $res = $db->query_hash({
                            'from' => $target_table,
                            'where' => join(' AND ', @where)
                        });
                        if (@{$res}) {
                            my $row = shift(@{$res});
                            my $new_row = {};
                            for my $k (keys %$r) {
                                if(!grep(/^$k$/, @groupFields)) {
                                    $new_row->{$k} = $row->{$k} + $r->{$k};
                                }
                            }
                            $db->update($target_table, $new_row, \@where);
                        } else {
                            $r->{'date'} = "$year-$month-01";
                            $db->insert($target_table, $r);
                        }
                    }
                }
                $db->update('report_consolidation',
                    { 'last_date' => "timestamp with time zone 'epoch' + $last_time * interval '1 second'" },
                    [ "report_table = '$target_table'" ],
                );
            }
            if($month == 12) {
                $month = 1;
                $year++;
            } else {
                $month++;
            }
        }
    }
}

sub consolidateReportQueries
{
    return [];
}

sub logReportInfo
{
    return [];
}

sub consolidateReportInfoQueries
{
    return [];
}

sub consolidateReportInfo
{
    my ($self) = @_;

    my $db = EBox::DBEngineFactory::DBEngine();

    my $queries = $self->consolidateReportInfoQueries();

    for my $q (@{$queries}) {
        my $target_table = $q->{'target_table'};
        my $query = $q->{'query'};

        my $res = $db->query_hash({
            'select' => 'EXTRACT(EPOCH FROM last_date) AS date',
            'from' => 'report_consolidation',
            'where' => "report_table = '$target_table'"
        });

        my $date;
        if(@{$res}) {
            my $row = shift(@{$res});
            $date = $row->{'date'};
        } else {
            $res = $db->query_hash({
                'select' => 'EXTRACT(EPOCH FROM timestamp) AS date',
                'from' => $query->{'from'},
                'order' => "timestamp",
                'limit' => 1
            });
            my $row = shift(@{$res});
            #substract one so we can run the query with > and still get this
            #result in
            $date = $row->{'date'} - 1;

            #later we call update so we need to have something inserted
            $db->insert('report_consolidation', {
                'report_table' => $target_table,
                'last_date' => 'epoch'
            });
        }
        my @time = localtime($date);
        my $year = $time[5]+1900;
        my $month = $time[4]+1;

        my @curtime = localtime();
        my $curyear = $curtime[5]+1900;
        my $curmonth = $curtime[4]+1;

        my $orig_where = $query->{'where'};
        while (
            ($year < $curyear) or
            (($year == $curyear) and ($month <= $curmonth))
        ) {
            my $date_where = "timestamp > (timestamp with time zone 'epoch' + $date * interval '1 second') AND timestamp >= '$year-$month-01 00:00:00' AND " .
                "timestamp < date '$year-$month-01 00:00:00' + interval '1 month'";
            my $time_res = $db->query_hash({
                'select' => 'EXTRACT(EPOCH FROM timestamp) AS date',
                'from' => $query->{'from'},
                'where' => $date_where,
                'order' => 'date DESC',
                'limit' => 1
            });
            my $time_row = shift(@{$time_res});
            my $last_time = $time_row->{'date'};

            if (defined($last_time)) {
                $date_where = "timestamp > (timestamp with time zone 'epoch' + $date * interval '1 second') AND timestamp >= '$year-$month-01 00:00:00' AND " .
                    "timestamp <= timestamp with time zone 'epoch' + $last_time * interval '1 second'";
                my $new_where;
                if (defined($orig_where)) {
                    $new_where = "$orig_where AND $date_where";
                } else {
                    $new_where = "$date_where";
                }
                my $max_where = "timestamp = (SELECT MAX(timestamp) FROM " . $query->{'from'} . ' WHERE ' . $new_where . ')';
                $query->{'where'} = $max_where;

                my $results = $db->query_hash($query);
                if (@{$results}) {
                    my @fields = keys(%{@{$results}[0]});
                    if (defined($query->{'key'})) {
                        my @keyFields = split(/ *, */,$query->{'key'});
                        for my $r (@{$results}) {
                            my @where;
                            for my $f (@keyFields) {
                                push(@where, $f . " = '" . $r->{$f} . "'");
                            }
                            push(@where, "date = '$year-$month-01'");
                            my $res = $db->query_hash({
                                'from' => $target_table,
                                'where' => join(' AND ', @where)
                            });
                            if (@{$res}) {
                                my $new_row = {};
                                for my $k (keys %$r) {
                                    if(!grep(/^$k$/, @keyFields)) {
                                        $new_row->{$k} = $r->{$k};
                                    }
                                }
                                $db->update($target_table, $new_row, \@where);
                            } else {
                                $r->{'date'} = "$year-$month-01";
                                $db->insert($target_table, $r);
                            }
                        }
                    } else {
                        for my $r (@{$results}) {
                            my @where;
                            push(@where, "date = '$year-$month-01'");
                            my $res = $db->query_hash({
                                'from' => $target_table,
                                'where' => join(' AND ', @where)
                            });
                            if (@{$res}) {
                                my $new_row = {};
                                for my $k (keys %$r) {
                                    $new_row->{$k} = $r->{$k};
                                }
                                $db->update($target_table, $new_row, \@where);
                            } else {
                                $r->{'date'} = "$year-$month-01";
                                $db->insert($target_table, $r);
                            }
                        }
                    }
                }
                $db->update('report_consolidation',
                    { 'last_date' => "timestamp with time zone 'epoch' + $last_time * interval '1 second'" },
                    [ "report_table = '$target_table'" ],
                );
            }
            if($month == 12) {
                $month = 1;
                $year++;
            } else {
                $month++;
            }
        }
    }
}

1;
