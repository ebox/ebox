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

package EBox::Backup;

use strict;
use warnings;

use EBox::Config;
use EBox::Global;
use EBox::Exceptions::Internal;
use EBox::Exceptions::MissingArgument;
use EBox::Gettext;
use EBox::FileSystem;
use EBox::ProgressIndicator;

use File::Temp qw(tempdir);
use File::Copy qw(copy move);
use File::Slurp qw(read_file write_file);
use File::Basename;

use Error qw(:try);
use Digest::MD5;
use EBox::Sudo qw(:all);
use POSIX qw(strftime);
use DirHandle;
use Perl6::Junction qw(any all);

use Params::Validate qw(validate_with validate_pos);
use Filesys::Df;

use Readonly;
Readonly::Scalar our $FULL_BACKUP_ID  => 'full backup';
Readonly::Scalar our $CONFIGURATION_BACKUP_ID  =>'configuration backup';
Readonly::Scalar our $BUGREPORT_BACKUP_ID  =>'bugreport configuration dump';
my $RECURSIVE_DEPENDENCY_THRESHOLD = 3;

sub new 
{
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

# returns:
# 	string: path to the backup file.
sub _makeBackup # (description, bug?) 
{
	my ($self, %options) = @_;

	my $bug         = delete $options{bug};
	my $description = delete $options{description};

	my $progress   = $options{progress};


	my $time = strftime("%F %T", localtime);

	my $confdir = EBox::Config::conf;
	my $tempdir = tempdir("$confdir/backup.XXXXXX") or
		throw EBox::Exceptions::Internal("Could not create tempdir.");
	my $auxDir = "$tempdir/aux";
	my $archiveContentsDirRelative = "eboxbackup";
	my $archiveContentsDir = "$tempdir/$archiveContentsDirRelative";
	my $backupArchive = "$confdir/eboxbackup.tar";
	
	try {
	  mkdir($auxDir) or
	    throw EBox::Exceptions::Internal("Could not create auxiliar tempdir.");
	  mkdir($archiveContentsDir) or
	    throw EBox::Exceptions::Internal("Could not create archive tempdir.");

	  $self->_dumpModulesBackupData($auxDir, %options);

	  if ($bug) {
	    $self->_bug($auxDir);
	  }


	  if ($progress) {
	    $progress->setMessage(__('Creating backup archive'));
	    $progress->notifyTick();
	  }



	  my $filesArchive  = "$archiveContentsDir/files.tgz";
	  $self->_createFilesArchive($auxDir, $filesArchive);
	  $self->_createMd5DigestForArchive($filesArchive, $archiveContentsDir);
	  $self->_createDescriptionFile($archiveContentsDir, $description);
	  $self->_createDateFile($archiveContentsDir, $time);
	  $self->_createTypeFile($archiveContentsDir, $options{fullBackup}, $bug);
	  $self->_createModulesListFile($archiveContentsDir);

	  $self->_createSizeFile($archiveContentsDir);

	  $self->_createBackupArchive($backupArchive, $tempdir, $archiveContentsDirRelative);


	}
	finally {
	  system "rm -rf $tempdir";
	  if ($? != 0) {
	    EBox::error("$auxDir cannot be deleted: $!. Please do it manually");
	  }
	};

	return $backupArchive;
}


sub _dumpModulesBackupData
{
  my ($self, $auxDir, %options) = @_;

  my $progress   = $options{progress};

  my $global = EBox::Global->getInstance();
  my @names = @{$global->modNames};
  foreach my $modName (@names) {
    my $mod = $global->modInstance($modName);

    if ($progress) {
      # update progress object
      $progress->notifyTick();
      $progress->setMessage(__x('Dumping configuration of module {m}',
			      m => $modName));
    }


    try {
      EBox::debug("Dumping $modName backup data");
      $mod->makeBackup($auxDir, %options);
    } 
    catch EBox::Exceptions::Base with {
      my $ex = shift;
      throw EBox::Exceptions::Internal($ex->text);
    };
  }

}

sub  _createFilesArchive
{
  my ($self, $auxDir, $filesArchive) = @_;

  if (`tar czf $filesArchive -C $auxDir .`) {
    throw EBox::Exceptions::Internal("Could not create archive.");
  }
  `rm -rf $auxDir`;

} 

sub  _createDateFile
{
  my ($self, $archiveContentsDir, $time) = @_;

  my $DATE;
  unless (open($DATE, "> $archiveContentsDir/date")) {
    throw EBox::Exceptions::Internal ("Could not create date file.");
  }
  print $DATE  $time ;
  close($DATE);
} 

sub  _createDescriptionFile
{
  my ($self, $archiveContentsDir, $description) = @_;

  my $DESC;
  unless (open($DESC, "> $archiveContentsDir/description")) {
    throw EBox::Exceptions::Internal ("Could not create description file.");
  }
  print $DESC $description;
  close($DESC);
} 

sub  _createTypeFile
{
  my ($self, $archiveContentsDir, $fullBackup, $bug) = @_;

  my $type =    $bug        ? $BUGREPORT_BACKUP_ID 
              : $fullBackup ?  $FULL_BACKUP_ID 
	      :	$CONFIGURATION_BACKUP_ID;

  my $TYPE_F;
  unless (open($TYPE_F, "> $archiveContentsDir/type")) {
    throw EBox::Exceptions::Internal ("Could not create type file.");
  }
  print $TYPE_F $type;
  close($TYPE_F);
} 

sub _createMd5DigestForArchive
{
  my ($self, $filesArchive, $archiveContentsDir) = @_;
  
  my $ARCHIVE;
  unless (open($ARCHIVE, $filesArchive)) {
    throw EBox::Exceptions::Internal("Could not open files archive.");
  }
  my $md5 = Digest::MD5->new;
  $md5->addfile($ARCHIVE);
  my $digest = $md5->hexdigest;
  close($ARCHIVE);

  my $MD5;
  unless (open($MD5, "> $archiveContentsDir/md5sum")) {
    throw EBox::Exceptions::Internal("Could not open md5 file.");
  }
  print $MD5 $digest;
  close($MD5);
}


sub  _createModulesListFile
{
  my ($self, $archiveContentsDir) = @_;

  my $global = EBox::Global->getInstance();
  my @modNames = @{ $global->modNames() };

  my $file = "$archiveContentsDir/modules";
  write_file($file, "@modNames");
} 

sub  _createBackupArchive
{
  my ($self, $backupArchive, $tempdir, $archiveContentsDirRelative) = @_;

  if ( -f $backupArchive) {
    if (`rm -f $backupArchive`) {
      throw EBox::Exceptions::Internal	("Could not delete old file.");
    }
  }

  my $filesArchive = "$archiveContentsDirRelative/files.tgz";
  my $cmd;
  my @output;

  $cmd = "tar cf $backupArchive -C $tempdir $archiveContentsDirRelative  --exclude $filesArchive 2>&1";
  @output = `$cmd`;
  if ($? != 0) {
    EBox::error("Failed command: $cmd. Output: @output");
    throw EBox::Exceptions::External(__('Could not create backup archive'));
  }

  $cmd = "tar --append -f $backupArchive  -C $tempdir $filesArchive 2>&1";
  @output = `$cmd`;
  if ($? != 0) {
    EBox::error("Failed command: $cmd. Output: @output");
    throw EBox::Exceptions::External(__('Could not append data to backup archive'));
  }
} 

sub _createSizeFile
{
  my ($self,  $archiveContentsDir) = @_;
  my $size;
  
  my $duCommand = "du -b -s -c --block-size=1024 $archiveContentsDir";
  my $output    = EBox::Sudo::command($duCommand);
  my ($totalLine) = grep { m/total/  } @{ $output  };
  ($size) = split '\s', $totalLine; 

  my $sizeFile = "$archiveContentsDir/size";
  write_file($sizeFile, $size)
} 



sub _bug # (dir) 
{
	my ($self, $dir) = @_;
	`/bin/ps aux > $dir/processes`;
	`/bin/df -k > $dir/disks`;
	`/bin/netstat -n -a --inet > $dir/sockets`;
	`/sbin/ifconfig -a > $dir/interfaces`;

	try {
		root("/sbin/iptables -nvL > $dir/iptables-filter");
	} catch EBox::Exceptions::Base with {};

	try {
		root("/sbin/iptables -t nat -nvL > $dir/iptables-nat");
	} catch EBox::Exceptions::Base with {};

	copy(EBox::Config::logfile, "$dir/ebox.log");
	copy(EBox::Config::log . "/error.log", "$dir/error.log");
	copy("/var/log/syslog", "$dir/syslog");
	copy("/var/log/messages", "$dir/messages");
	copy("/var/log/daemon.log", "$dir/daemon.log");
	copy("/var/log/auth.log", "$dir/auth.log");
}

#
# Method: backupDetails 
#
#   	Gathers the information for a given backup
#
# Parameters:
#
#       id - backup's identifier
#
# Returns:
#
#       A hash reference with the details. This hash consists of:
#	
#       file - the filename of the archive
#	id - backup's identifier
#	date - when it was backed up
#       type - the type of backup
#	description - backup's description
#
sub backupDetails # (id) 
{
  my ($self, $id) = @_;
  validate_pos(@_, 1, ,1);

  $self->_checkId($id);

  my $file = $self->_backupFileById($id);

  my $details = $self->backupDetailsFromArchive($file);
  $details->{id} = $id;
  
  return $details;
}


#
# Method: backupDetailsFromArchive
#
#      Gathers the details of the backup stored in a given file
#
#
# Parameters:
#       archive - the path to the archive file
#       
#
# Returns:
#
#       A hash reference with the details. This hash consists of:
#	
#       file - the filename of the archive
#	date - when it was backed up
#	description - backup's description
#       type        - the type of backup contained by the archive
sub backupDetailsFromArchive
{
  my ($self, $archive) = @_;
  validate_pos(@_, 1, 1);

  my $backupDetails = {};

  my @details = qw(date description type);
  my $tempDir = $self->_unpackArchive($archive, @details);


  foreach my $detail (@details) {
    my $FH;
    unless (open($FH, "$tempDir/eboxbackup/$detail")) {
      $backupDetails->{$detail} = __('Unknown');
      next;
    }

    my $value = <$FH>;
    $backupDetails->{$detail} = $value;

    close $FH;
  }

  $backupDetails->{file} = $archive; 

  system "rm -rf $tempDir";
  return $backupDetails;
}

# if not specific files are specified all the fiels are  extracted
sub _unpackArchive
{
  my ($self, $archive, @files) = @_;
  ($archive) or throw EBox::Exceptions::External('No backup archive provided.');

  my $tempDir = tempdir(EBox::Config::tmp . "/backup.XXXXXX") or
    throw EBox::Exceptions::Internal("Could not create tempdir.");

  my $filesWithPath =  @files > 0 ?
    join ' ', map { 'eboxbackup/' . $_  } @files : '';

  try {
    
    my $tarCommand = "/bin/tar xf $archive -C $tempDir $filesWithPath";
    if (system $tarCommand) {
      if (@files > 0) {
	throw EBox::Exceptions::External( __x("Could not extract the requested backup files: {files}", files => "@files"));
      }
      else {
	throw EBox::Exceptions::External( __("Could not unpack the backup"));
      }
    }

  }
  otherwise {
    my $ex = shift;
    
    system("rm -rf $tempDir");
    ($? == 0) or EBox::warning("Unable to remove $tempDir. Please do it manually");

    $ex->throw();
  };

  return $tempDir;
}


#
# Method: deleteBackup 
#
#   	Romoves a stored backup	
#
# Parameters:
#
#       id - backup's identifier
#
# Exceptions:
#
#     	External -  If it can't be found or deleted.
sub deleteBackup # (id) 
{
  my ($self, $id) = @_;
  validate_pos(@_, 1, 1);

  $self->_checkId($id);
	
  my $file = $self->_backupFileById($id);

  unless (unlink($file)) {
    throw EBox::Exceptions::External("Could not delete the backup");
  }
}


#
# Method: listBackups 
#
#   	Returns a list with the availible backups stored in the system.	
#
# Parameters:
#
#       id - backup's identifier
#
# Returns:
#
#       A a ref to an array of hashes. Each  hash reference consists of:
#	
#	id - backup's identifier
#	date - when it was backed up
#	description - backup's description
#       type        - type of backup (full or configuration only)
#
sub listBackups
{
	my $self = shift;
	my $backupdir = backupDir();
	my $bh = new DirHandle($backupdir);
	my @backups = ();
	my $backup;
	($bh) or return \@backups;
	while (defined($backup = $bh->read)) {
		(-f "$backupdir/$backup") or next;
		$backup =~ s/\.tar$//;
		my $entry = undef;
		try {
			$entry = $self->backupDetails($backup);
		} catch EBox::Exceptions::Base with {};
		unless ($entry) {
			unlink("$backupdir/$backup.tar");
			next;
		}
		push(@backups, $entry);
	}
	undef $bh;
	my @ret = sort {$a->{date} lt $b->{date}} @backups;
	return \@ret;
}

#
# Procedure: backupDir  
#
# Returns: 
#       the directory used by ebox to store the backup archives 
#
# 
sub backupDir
{
  my $backupdir = EBox::Config::conf . '/backups';
  return $backupdir;
}


sub _ensureBackupdirExistence
{
  my $backupdir = backupDir();

  unless (-d $backupdir) {
    mkdir($backupdir) or throw EBox::Exceptions::Internal
      ("Could not create backupdir.");
  }

  
} 




#
# Method: prepareMakeBackup
#
#   	Prepares a backup restauration 
#
# Parameters:
#
#                   description - backup's description (backwards compability mode)
#                   fullBackup  - wether do a full backup or  backup only configuration (default: false)
#
#  Returns:
#    the progress indicator object whihc represents the progress of the restauration
#
# Exceptions:
#	
#	External - If it can't unpack de backup
#
sub prepareMakeBackup
{
  my ($self, @options) = @_;

  my $makeBackupScript = EBox::Config::libexec() . 'ebox-make-backup';
  $makeBackupScript    .= "  @options";
  
  my $global     = EBox::Global->getInstance();
  my $totalTicks = scalar @{ $global->modNames } + 2; # there are one task for
                                                      # each module plus two
                                                      # tasks for writing the
                                                      # archive  file
           

  my $progressIndicator =  EBox::ProgressIndicator->create(
			     executable => $makeBackupScript,
			     totalTicks => $totalTicks,
						    );

  $progressIndicator->runExecutable();

  return $progressIndicator;
}


#
# Method: makeBackup 
#
#   	Backups the current configuration	
#
# Parameters:
#
#                   progressIndicatorId - Id of the progress indicator 
#                       associated with this operation (mandatory )
#                   description - backup's description (default: 'Backup')
#                   fullBackup  - wether do a full backup or  backup only configuration (default: false)
#
# Exceptions:
#	
#	Internal - If backup fails
#       Exteanl   - If modules have unsaved changes
sub makeBackup # (options) 
{
  my ($self, %options) = @_;
  validate_with(
		params => [%options],
		spec   => {
			   progress     => { 
					    optional => 0, 
					     isa => 'EBox::ProgressIndicator'
					   },
			   description => { default =>  __('Backup') },
			   fullBackup  => { default => 0 },
			  });

  my $progress = $options{progress};
  EBox::debug("make backup id: " . $progress->id());
  $progress->started or
    throw EBox::Exceptions::Internal("ProgressIndicator's executable has not been run");
  
  
  my $backupdir = backupDir();

  my $filename;
  try {
    $self->_modulesReady();
    
    _ensureBackupdirExistence();

    $filename = $self->_makeBackup(%options);
  }
 otherwise {
   my $ex = shift @_;
   $progress->setAsFinished();
   $ex->throw();
 };


  my $retValue;
  try {
      $progress->notifyTick();
      $progress->setMessage(__('Writing backup file to hard disc'));

      $retValue = $self->_moveToArchives($filename, $backupdir);      
  }
  finally {
    $progress->setAsFinished();
  };
    

  return $retValue;
}


sub _modulesReady
{
  my ($self) = @_;

  my $global = EBox::Global->getInstance();
  foreach my $modName (@{ $global->modNames }) {
    if ($global->modIsChanged($modName)) {
      throw EBox::Exceptions::External(
	 __('Some modules has not saved changes. Before doing the backup you must'
	    . ' save  or discard them' ) );				      
    }
}

}

sub  _moveToArchives
{
  my ($self, $filename, $backupdir) = @_;

  my $id = int(rand(999999)) . ".tar";
  while (-f "$backupdir/$id") {
    $id = int(rand(999999)) . ".tar";
  }

  move($filename, "$backupdir/$id") or
    throw EBox::Exceptions::Internal("Could not save the backup.");

  return "$backupdir/$id";
} 


#
# Method: makeBugReport
#
#   	Makes a bug report	
#
sub makeBugReport
{
	my $self = shift;
	return $self->_makeBackup(description => 'Bug report', 'bug' => 1);
}

# unpacks a backup file into a temporary directory and verifies the md5sum
# arguments:
# 	string: backup file
# returns:
# 	string: path to the temporary directory
sub _unpackAndVerify # (file, fullRestore) 
{
  my ($self, $archive, $fullRestore) = @_;
  ($archive) or throw EBox::Exceptions::External('No backup file provided.');
  my $tempdir;

  try {
    # 	  unless (copy($file, "$tempdir/eboxbackup.tar")) {
    # 	    throw EBox::Exceptions::Internal("Could not copy backup into ".
    # 					     "the tempdir.");
    # 	  }

    $tempdir = $self->_unpackArchive($archive);

    unless ( -f "$tempdir/eboxbackup/files.tgz" && 
	     -f "$tempdir/eboxbackup/md5sum") {
      throw EBox::Exceptions::External( __('Incorrect or corrupt backup file'));
    }

    $self->_checkArchiveMd5Sum($tempdir);
    $self->_checkArchiveType($tempdir, $fullRestore);
  }
  otherwise {
    my $ex = shift;

    if (defined $tempdir) {
      system("rm -rf $tempdir");
      ($? == 0) or EBox::warning("Unable to remove $tempdir. Please do it manually");
    }

    $ex->throw();
  };

  return $tempdir;
}

sub  _checkArchiveMd5Sum
{
  my ($self, $tempdir) = @_;


  my $archiveFile = "$tempdir/eboxbackup/files.tgz";
  my $ARCHIVE;
  unless (open($ARCHIVE, $archiveFile)) {
    EBox::error("Cannot open archive file $archiveFile");
    throw EBox::Exceptions::External(__("The backup file is corrupt: could not open archive"));
  }
  my $md5 = Digest::MD5->new;
  $md5->addfile($ARCHIVE);
  my $digest = $md5->hexdigest;
  close($ARCHIVE);


  my $md5File = "$tempdir/eboxbackup/md5sum";
  my $MD5;
  unless (open($MD5, $md5File)) {
    EBox::error("Could not open the md5sum $md5File");
    throw EBox::Exceptions::External(__("The backup file is corrupt: could not open backup checksum"));
  }
  my $olddigest = <$MD5>;
  close($MD5);

  if ($digest ne $olddigest) {
    throw EBox::Exceptions::External(
				     __('The backup file is corrupt.'));
  }
}

sub _checkArchiveType
{
  my ($self, $tempdir, $fullRestore) = @_;

  my $typeFile = "$tempdir/eboxbackup/type";
  my $TYPE_F;
  unless (open($TYPE_F, $typeFile )) {
    EBox::error("Cannot open type file: $typeFile");
    throw EBox::Exceptions::External("The backup file is corrupt. Backup type information not found");
  }
  my $type = <$TYPE_F>;
  close($TYPE_F);
  
  if ($type ne all($FULL_BACKUP_ID, $CONFIGURATION_BACKUP_ID, $BUGREPORT_BACKUP_ID)) {
    throw EBox::Exceptions::External(__("The backup archive has a invalid type. Maybe the file is corrupt or you are using a incompatible eBox version"));
  }


  if ($fullRestore) {
    if ($type ne $FULL_BACKUP_ID) {
      throw EBox::Exceptions::External(__('The archive does not contain a full backup, that made a full restore impossibe. A configuration recovery  may be possible'));
    }
  } 

}



sub  _checkSize
{
  my ($self, $archive) = @_;

  my $size;
  my $freeSpace;
  my $safetyFactor = 2; # to be sure we have space left we multiply the backup
                        # size by this number. The value was guessed, so change
                        # it if you have better judgment

  my $tempDir;
  try {
    $tempDir = $self->_unpackArchive($archive, 'size'); 
    $size = read_file("$tempDir/eboxbackup/size"); # unit -> 1K
  }
  finally {
    if (defined $tempDir) {
      system("rm -rf $tempDir");
      ($? == 0) or EBox::warning("Unable to remove $tempDir. Please do it manually");
    }
  };


  my $backupDir = $self->backupDir();
  $freeSpace = df($backupDir, 1024)->{bfree};

  if ($freeSpace < ($size*$safetyFactor)) {
    throw EBox::Exceptions::External(__x("There in not enough space left in the hard disk to complete the restore proccess. {size} Kb required. Free sufficient space and retry", size => $size));
  }

} 

 
#
# Method: prepareRestoreBackup
#
#   	Prepares a backup restauration 
#
# Parameters:
#
#       file - backup's file (as positional parameter)
#       fullRestore  - wether do a full restore or  restore only configuration (default: false)
#
#  Returns:
#    the progress indicator object whihc represents the progress of the restauration
#
# Exceptions:
#	
#	External - If it can't unpack de backup
#
sub prepareRestoreBackup
{
  my ($self, $file, @options) = @_;

  my $restoreBackupScript = EBox::Config::libexec() . 'ebox-restore-backup';
  $restoreBackupScript    .= " file $file @options";
  
  my $totalTicks = scalar @{ $self->_modInstancesForRestore };

  my $progressIndicator =  EBox::ProgressIndicator->create(
			     executable => $restoreBackupScript,
			     totalTicks => $totalTicks,
						    );

  $progressIndicator->runExecutable();

  return $progressIndicator;
}


#
# Method: restoreBackup 
#
#   	Restores a backup from file	
#
# Parameters:
#
#       file - backup's file (as positional parameter) 
#       progressIndicatorId - Id of the progress indicator associated
#                       with htis operation (mandatory )
# fullRestore - wether do a full restore or restore only configuration (default: false)
#
# Exceptions:
#	
#	External - If it can't unpack de backup
#
sub restoreBackup # (file, %options) 
{
  my ($self, $file, %options) = @_;
  defined $file or throw EBox::Exceptions::MissingArgument('Backup file');

  validate_with ( params => [%options], 
		  spec => { 
			   progress    => {
					   optional => 0,
					   isa => 'EBox::ProgressIndicator',
					  },
			   fullRestore => { default => 0 },  
			  });

  _ensureBackupdirExistence();
  $self->_checkSize($file);

  my $progress = delete $options{progress}; # we don't need to pass the progress
                                            # object to any methos, so we remove
                                            # it from the options
  EBox::debug("restore backup id: " . $progress->id);
  $progress->started or
    throw EBox::Exceptions::Internal("ProgressIndicator's executable has not been run");

  my $tempdir = $self->_unpackAndVerify($file, $options{fullRestore});

  try {
    if (`tar xzf $tempdir/eboxbackup/files.tgz -C $tempdir/eboxbackup`) {
      `rm -rf $tempdir`;
      throw EBox::Exceptions::External(
				       __('Could not unpack the backup'));
    }

    my @modules  = @{ $self->_modInstancesForRestore() };
    my @restored = ();
    try {
      foreach my $mod (@modules) {
	my $modname = $mod->name();

	# update progress indicator 
	$progress->notifyTick(); 
	$progress->setMessage($modname);

	my $restoreOk = $self->_restoreModule($mod, $tempdir, \%options);
	if ($restoreOk) {
	  push @restored, $modname;
	}

      }

    } 
    otherwise {
      my $ex = shift;

      EBox::error('Error while restoring: ' . $ex->text());

      $self->_revokeRestore(\@restored);
      throw $ex;
    }
    finally {
      $progress->setAsFinished(); #
    };


    EBox::info('Restore successful');
  }
  finally {
      system 'rm -rf $tempdir';
  };
}


sub _restoreModule
{
  my ($self, $mod, $tempdir, $options_r) = @_;
  my $modname = $mod->name();

  if (not -e "$tempdir/eboxbackup/$modname.bak") {
    EBox::error("Restore data not found for module $modname. Skipping $modname restore");
    return 0;
  }

  EBox::debug("Restoring $modname from backup data");
  $mod->setAsChanged(); # we set as changed first because it is not
  # guaranteed that a failed backup will not
  # change state
  $mod->restoreBackup("$tempdir/eboxbackup", %{ $options_r });
  $self->_migratePackage($mod->package());
  
  return 1;
}


sub _revokeRestore
{
  my ($self, $restored_r) = @_;

  EBox::debug('revoking restore for all modules');
  foreach my $restname (@{ $restored_r }) {
    my $restmod = EBox::Global->modInstance($restname);
    try {
      $restmod->revokeConfig();
      # XXX remember no-gconf changes are not revoked!
      EBox::debug("Revoked changes in $restname module");
    }
    otherwise {
      EBox::debug("$restname has not changes to be revoked" );
    };
  }
}

sub _migratePackage
{
	my ($self, $package) = @_;
	my $migrationdir = EBox::Config::lib() . "/$package/migration";
	
	if (-d $migrationdir) {
		my $migration = EBox::Config::libexec() . '/ebox-migrate';
		try {
			EBox::Sudo::command("$migration $migrationdir");
		} catch EBox::Exceptions::Internal with {
			EBox::debug("Failed to migrate $package");
		};
	}
}


sub _modInstancesForRestore
{
  my ($self) = @_;
  my $global = EBox::Global->getInstance();

  # we remove global module because it will be  the first to be restored
  my @modules   =  grep { $_->name ne 'global' } @{$global->modInstances() };   

  # check modules dependencies
  foreach my $mod (@modules) {
    $self->_checkModDeps($mod->name);
  }

  # we sort the modules list with a restore-safe order
  my %anyDependencyByModule = map {
    my $mod = $_;
    my $anyDependency = any(  @{ $mod->restoreDependencies() } );
    ($mod => $anyDependency);
  } @modules;


  @modules = sort {
    my $aDependsB =  $anyDependencyByModule{$a} eq $b->name() ? 1 : 0;
    my $bDependsA =  $anyDependencyByModule{$b} eq $a->name() ? 1 : 0;

    $aDependsB <=> $bDependsA;
  } @modules;

  # we restore global in first place to avoid false changed info
  unshift @modules, $global; 

  return \@modules;
}




sub _checkModDeps
{
  my ($self, $modName, $level, $topModule) = @_;
  defined $level or $level = 0;

  if ($level == 0) {
    $topModule = $modName;
  }
 
  if ($level >= $RECURSIVE_DEPENDENCY_THRESHOLD) {
    throw EBox::Exceptions::Internal('Recursive restore dependency found.');
  }

  my $global = EBox::Global->getInstance();
  my $mod = $global->modInstance($modName);

  if (not defined $mod) {
    if ($level == 0) {
      throw EBox::Exceptions::Internal ("$topModule can not be created again");
    }
    else {
      throw EBox::Exceptions::External __x('Unresolved restore dependency for module {topModule}: {modName} is not installed', topModule => $topModule, modName => $modName  );
    }
  }

  my @dependencies = @{$mod->restoreDependencies};
  foreach my $dep (@dependencies) {
    if ($dep eq $modName) {
      throw EBox::Exceptions::Internal ("$modName depends on it self. Maybe something is wrong in _modInstancesForRestore method?. $modName will not be restored");
    }

    $self->_checkModDeps($dep, $level +1, $topModule);
  }
}



sub _checkId
{
  my ($self, $id) = @_;  
  if ($id =~ m{[./]}) {
		throw EBox::Exceptions::External(
			__("The input contains invalid characters"));
	}
}

sub _backupFileById
{
    my ($self, $id) = @_;

    my $backupdir = EBox::Config::conf . '/backups';
    my $file = "$backupdir/$id.tar";
    unless (-f $file) {
	throw EBox::Exceptions::External("Could not find the backup.");
    }

    return $file;
}

#  Function: _facilitiesForDiskUsage
#  Overrides: EBox::Report::DiskUsageProvider::_faciltiesForDiskUsage
sub _facilitiesForDiskUsage
{
  return {
	  __(q{Backup's archives}) => [ backupDir() ],
	 }
}

1;
