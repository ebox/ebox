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

package EBox::Backup::Test;

use strict;
use warnings;

use lib '../..';

use base 'EBox::Test::Class';

use Test::MockObject;
use Test::More;
use Test::Exception;
use Test::Differences;
use EBox::Test qw(checkModuleInstantiation);
use EBox::TestStubs qw(fakeEBoxModule);
use EBox::Gettext;
use File::Slurp qw(read_file write_file);
use EBox::FileSystem qw(makePrivateDir);
use Perl6::Junction qw(all);

use Readonly;
Readonly::Scalar my $GCONF_CANARY_KEY => '/ebox/modules/canaryGConf/canary';
Readonly::Scalar my $GCONF_EXTENDED_CANARY_KEY => '/ebox/modules/canaryExtended/key';
Readonly::Scalar my $GCONF_MIXEDCONF_CANARY_KEY => '/ebox/modules/canaryMixedConf/key';
Readonly::Scalar my $CANARY_MODULE_VERSION => 'canary 0.1';

sub testDir
{
  return '/tmp/ebox.backup.test';
}



sub notice : Test(startup)
{
  diag 'This test use GConf and may left behind some test entries in the tree /ebox';
  diag 'Remember you need the special GConf packages from eBox repository. Otherwise these tests will fail in awkward ways';
}


sub setupDirs : Test(setup)
{
  my ($self) = @_;

  return if !exists $INC{'EBox/Backup.pm'};

  EBox::TestStubs::setEBoxConfigKeys(conf => testDir(), tmp => $self->testDir());

  my $testDir = $self->testDir();
  system "rm -rf $testDir";

  makePrivateDir($testDir);

  system "rm -rf /tmp/backup";
  ($? == 0) or die $!;
  makePrivateDir('/tmp/backup');
}



sub _useOkTest : Test(1)
{
  use_ok('EBox::Backup');
}




sub setUpCanaries : Test(setup)
{
  my ($self) = @_;

  setupGConfCanary();
  setupExtendedCanary();
  setupMixedConfCanary();
}


sub setupGConfCanary
{
  fakeEBoxModule(
		 name => 'canaryGConf',
		);
}

sub setupExtendedCanary
{

  fakeEBoxModule(
		 name => 'canaryExtended',
		 subs => [
			  setCanary => sub { my ($self, $canary) = @_; $self->{canary} = $canary },
			  canary => sub { my ($self) = @_; return $self->{canary} },
			  setVersion => sub { my ($self, $version) = @_; $self->{version} = $version },
			  version => sub { my ($self) = @_; return $self->{version} },
			  extendedBackup => sub {
			    my ($self, %params) = @_;
			    my $dir = $params{dir};
			    write_file ("$dir/canary", $self->{canary} );
			  },
			  extendedRestore => sub {
			    my ($self, %params) = @_;
			    my $dir = $params{dir};
			    my $versionInfo = $params{version};
			    my $backedUpData =  read_file ("$dir/canary" );
			    $self->setCanary($backedUpData);
			    $self->setVersion($versionInfo);
			  },
			 ],
		);

}

sub setupMixedConfCanary
{


 fakeEBoxModule(
		 name => 'canaryMixedConf',
		 subs => [
			  setCanary => sub { my ($self, $canary) = @_; $self->{canary} = $canary },
			  canary => sub { my ($self) = @_; return $self->{canary} },
			  setVersion => sub { my ($self, $version) = @_; $self->{version} = $version },
			  version => sub { my ($self) = @_; return $self->{version} },
			  dumpConfig => sub {
			    my ($self, $dir) = @_;
			    EBox::GConfModule::_dump_to_file($self, $dir);
			    write_file ("$dir/canary", $self->{canary} );
			  },
			  restoreConfig => sub {
			    my ($self, $dir) = @_;
			    EBox::GConfModule::_load_from_file($self, $dir);
			    my $backedUpData =  read_file ("$dir/canary" );
			    $self->setCanary($backedUpData);
			  },
			 ],
		);

}
 

sub setCanaries
{
  my ($value) = @_;

  setGConfCanary($value);
  setExtendedCanary($value);
  setMixedConfCanary($value);
}


sub setGConfCanary
{
  my ($value) = @_;
  _setGConfString($GCONF_CANARY_KEY, $value);

  my $canaryConf = EBox::Global->modInstance('canaryGConf');
  $canaryConf->setAsChanged();
}

sub setExtendedCanary
{
  my ($value) = @_;

  _setGConfString($GCONF_EXTENDED_CANARY_KEY, $value);

  my $canaryExtended = EBox::Global->modInstance('canaryExtended');
  $canaryExtended->setCanary($value);
  $canaryExtended->setVersion($CANARY_MODULE_VERSION);
  $canaryExtended->setAsChanged();

  die 'canary not changed' if $canaryExtended->canary() ne $value;
}
 

sub setMixedConfCanary
{
  my ($value) = @_;

  _setGConfString($GCONF_MIXEDCONF_CANARY_KEY, $value);


  my $canaryMixedConf = EBox::Global->modInstance('canaryMixedConf');
  $canaryMixedConf->setCanary($value);
  $canaryMixedConf->setAsChanged();

  die 'canary not changed' if $canaryMixedConf->canary() ne $value;
}

sub _setGConfString
{
  my ($key, $value) = @_;
  defined $key or die "Not key supplied";
  defined $value or die "Not value supplied for key $key";

  my $client = Gnome2::GConf::Client->get_default;
  defined $client or die "Can not retrieve GConf client";

  $client->set_string($key, $value);

  die "gconf key $key not changed" if $client->get_string($key) ne $value;
}


sub checkCanaries
{
  my ($expectedValue, $fullRestore) = @_;  

  checkGConfCanary($expectedValue);
  checkExtendedCanary($expectedValue, $fullRestore);
  checkMixedConfCanary($expectedValue);
}


sub checkGConfCanary
{
  my ($expectedValue) = @_;

  my $client = Gnome2::GConf::Client->get_default;
  my $value = $client->get_string($GCONF_CANARY_KEY);
  is $value, $expectedValue, 'Checking GConf data of simple module canary';
}

sub checkExtendedCanary
{
  my ($expectedValue, $fullRestore) = @_;
  my $client = Gnome2::GConf::Client->get_default;
  my $value;

  $value = $client->get_string($GCONF_EXTENDED_CANARY_KEY);
  is $value, $expectedValue, 'Checking GConf data of canary module with extended backup and restore';

  my $canaryExtended = EBox::Global->modInstance('canaryExtended');
  $value = $canaryExtended->canary();
  if ($fullRestore) {
    is $value, $expectedValue, 'Checking extra data of canary module with extended backup and restore';
  }
  else {
    isnt $value, $expectedValue, 'Checking extra data of canary module was not restored with configuration restore';
  }

  my $version  = $canaryExtended->version();
  is $version, $CANARY_MODULE_VERSION, 'Checking if version information was correctly backed';
}

sub checkMixedConfCanary
{
  my ($expectedValue) = @_;
  my $client = Gnome2::GConf::Client->get_default;
  my $value;

  $value = $client->get_string($GCONF_MIXEDCONF_CANARY_KEY);
  is $value, $expectedValue, 'Checking GConf configuration data of canary module with mixed config';

  my $canaryMixedConf = EBox::Global->modInstance('canaryMixedConf');
  $value = $canaryMixedConf->canary();
  is $value, $expectedValue, 'Checking no-GConf configuration  data of canary module with mixed config'
}




sub teardownGConfCanary : Test(teardown)
{

  my $client = Gnome2::GConf::Client->get_default;
  $client->unset($GCONF_CANARY_KEY);  
  $client->unset($GCONF_EXTENDED_CANARY_KEY);  
  $client->unset($GCONF_MIXEDCONF_CANARY_KEY);  
}

sub teardownCanaryModule : Test(teardown)
{
  my ($self) = @_;
  EBox::TestStubs::setConfig(); 
}

# that counts for 8 tests
sub checkStraightRestore
{
  my ($archiveFile, $options_r, $msg) = @_;

  my $backup = new EBox::Backup();
  setCanaries('afterBackup');
  lives_ok { $backup->restoreBackup($archiveFile, @{ $options_r  }) } $msg;

  my %options = @{ $options_r  };
  checkCanaries('beforeBackup', $options{fullRestore});

  checkModulesChanged(
	name => 'Checking wether all restored modules have the changed state set' 
		     );
}


sub checkModulesChanged
{
  my %params = @_;
  my $name  = $params{name};

  my $global = EBox::Global->getInstance();

  my @modules;
  if (exists $params{modules}) {
    @modules = @{ $params{modules} };
  }
  else {
    @modules = @{ $global->modNames() };
  }

  my @modulesChanged =  grep {  $global->modIsChanged($_) } @modules;

  is_deeply [sort @modulesChanged], [sort @modules], $name;
}


# that counts for 7 tests
sub checkDeviantRestore
{
  my ($archiveFile, $options_r, $msg) = @_;

  my $backup = new EBox::Backup();
  setCanaries('afterBackup');
  dies_ok { $backup->restoreBackup($archiveFile, @{ $options_r  }) } $msg;

  diag "Checking that failed restore has not changed the configuration";
  checkCanaries('afterBackup', 1);
}


sub checkMakeBackup
{
  my @backupParams = @_;

  my $global = EBox::Global->getInstance();
  $global->saveAllModules();

  my $backupArchive;
  my $b = new EBox::Backup;
  lives_ok { $backupArchive = $b->makeBackup(@backupParams)  } 'Checking wether backup is correctly done';
  
  return $backupArchive;
}


# this requires a correct testdata dir
sub invalidArchiveTest : Test(35)
{
  my ($self) = @_;
  my $incorrectFile = $self->testDir() . '/incorrect';
  system "cp $0 $incorrectFile";
  ($? == 0) or die "$!";
  checkDeviantRestore($incorrectFile, [], 'restoreBackup() called with a incorrect file');

  my @deviantFiles = (
		      ['badchecksum.tar', 'restoreBackup() called with a archive with fails checksum'],
		      ['badsize.tar', 'restoreBackup() called with a archive with uncompressed size exceeds available storage'],
		      ['missingtype.tar', 'restoreBackup() called with a archive missing type of backup information'],
		      ['badtype.tar', 'restoreBackup() called with a archive wuth incorrect backup type information'],
		     );

  foreach my $case (@deviantFiles) {
    my ($file, $msg) = @{ $case };
    $file = _testdataDir() . "/$file";
    (-f $file) or die "Unavailble test data file $file";

    checkDeviantRestore($file, [], $msg);
  }
}

sub _testdataDir 
{
  my $dir = __FILE__;
  $dir =~ s/Test\.pm/testdata/;

  return $dir;
}

sub restoreConfigurationBackupTest : Test(18)
{
  my ($self) = @_;
 
  my $configurationBackup;
  setCanaries('beforeBackup');
  $configurationBackup = checkMakeBackup(description => 'test configuration backup');
  checkStraightRestore($configurationBackup, [fullRestore => 0], 'configuration restore from a configuration backup');

  my $fullBackup;
  setCanaries('beforeBackup');
  $fullBackup = checkMakeBackup(description => 'test full backup', fullBackup => 1);
  checkStraightRestore($fullBackup, [fullRestore => 0], 'configuration restore from a full backup');
}


sub restoreBugreportTest : Test(16)
{
  my ($self) = @_;

  my $backup = new EBox::Backup();
  my $bugReportBackup;
 
  setCanaries('beforeBackup');
  lives_ok { $bugReportBackup = $backup->makeBugReport() } 'make a bug report';

  checkStraightRestore($bugReportBackup, [fullRestore => 0], 'configuration restore from a bugreport');

  checkDeviantRestore($bugReportBackup, [fullRestore => 1], 'full restore not allowed from a bug report');
}




sub restoreFullBackupTest : Test(17)
{
  my ($self) = @_;

  my $configurationBackup;
  setCanaries('beforeBackup');
  $configurationBackup = checkMakeBackup(description => 'test configuration backup', fullBackup => 0);
  checkDeviantRestore($configurationBackup, [fullRestore => 1], 'checking that a full restore is forbidden from a configuration backup' );

  my $fullBackup;
  setCanaries('beforeBackup');
  $fullBackup = checkMakeBackup(description => 'test full backup', fullBackup => 1);
  checkStraightRestore($fullBackup, [fullRestore => 1], 'full restore from a full backup');
}


sub restoreWithModulesMissmatchTest : Test(46)
{
  my ($self) = @_;
 
  setCanaries('beforeBackup');
  my $global       = EBox::Global->getInstance();
  my @modsInBackup = @{ $global->modNames() };
  
  my $backupFile = checkMakeBackup( fullBackup => 0 );  
  
  my @straightCases;

  # one more module
  push @straightCases, sub {
    fakeEBoxModule( name => 'superfluousModule', );
  };

  # additional module with met dependencies
  push @straightCases, sub {
    fakeEBoxModule( name => 'superfluousModule', 
		    subs => [
			     restoreDependencies => sub { return ['canaryGConf'] },
			    ],
		  );
  };

  # two additional modules with met dependencies between them
  push @straightCases, sub {
    fakeEBoxModule( name => 'superfluousModule1', );
    fakeEBoxModule( name => 'superfluousModule2', 
		    subs => [
			     restoreDependencies => sub { return ['superfluousModule1'] },
			    ],
		  );
  };


  my @deviantCases;

  # with a additional module with unmet dependencies
  push @deviantCases, sub {
    fakeEBoxModule( name => 'unmetDepModule', 
		    subs => [
			     restoreDependencies => sub { return ['inexistentModule'] },
			    ],
		  );
  };
  # with a recursive dependency
  push @deviantCases, sub {
    fakeEBoxModule( name => 'recursiveDepModule1', 
		    subs => [
			     restoreDependencies => sub { return ['recursiveDepModule2'] },
			    ],
		  );
    fakeEBoxModule( name => 'recursiveDepModule2', 
		    subs => [
			     restoreDependencies => sub { return ['recursiveDepModule1'] },
			    ],
		  );
  };
  # with a module which depends on itself
  push @deviantCases, sub {
    fakeEBoxModule( name => 'depOnItselfModule', 
		    subs => [
			     restoreDependencies => sub { return ['depOnItselfModule'] },
			    ],
		  );
  };
  

  my $backup = new EBox::Backup();
  foreach my $case (@straightCases) {
    setUpCanaries();
    setGConfCanary('afterBackup');
    setMixedConfCanary('afterBackup');

    $case->();

    # restore backup
    setCanaries('afterBackup');
    lives_ok { 
      $backup->restoreBackup($backupFile, fullRestore => 0) 
    } 'checking restore without dependencies problems'   ;
    
    # check after backup state
    checkCanaries('beforeBackup', 0);
    checkModulesChanged(
			name => 'Checking wether restored modules are marked as changed',
			modules => \@modsInBackup,
		       );
    
  
    teardownCanaryModule();
    teardownGConfCanary();
  }


  foreach my $case (@deviantCases) {
    setUpCanaries();
    setGConfCanary('afterBackup');
    setMixedConfCanary('afterBackup');

    $case->();

    checkDeviantRestore($backupFile, [ fullRestore => 0], , 'checking wether restore with unmet dependencies raises error');

    teardownGConfCanary();
  }
  

}


sub listBackupsTest : Test(5)
{
  my ($self) = @_;
  diag "The backup's details of id a are not tested for now. The date detail it is only tested as relative order";

  my $backup = new EBox::Backup();
  my @backupParams = (
		      [description => 'configuration backup', fullBackup => 0], 
		      [description => 'full backup', fullBackup => 1],
		      );
 
  setCanaries('indiferent configuration');
  


  foreach (@backupParams) {
    my $global = EBox::Global->getInstance();
    $global->saveAllModules();

    $backup->makeBackup(@{ $_ });
    sleep 1;
  }

  my @backups = @{$backup->listBackups()};
  is @backups, @backupParams, 'Checking number of backups listed';

  foreach my $backup (@backups) {
    my %backupParam = @{ pop @backupParams };
    my $awaitedDescription = $backupParam{description};
    my $awaitedType        = $backupParam{fullBackup} ? 'full backup' : 'configuration backup';

    is $backup->{description}, $awaitedDescription, 'Checking backup description';
    is $backup->{type}, $awaitedType, 'Checking backup type';
  }

  
}





sub backupDetailsFromArchiveTest : Test(9)
{
  setCanaries('beforeBackup');
  my $global = EBox::Global->getInstance();
  $global->saveAllModules();

  
  my $configurationBackupDescription = 'test configuration backup for detail test';
  my $configurationBackup = EBox::Backup->makeBackup(description => $configurationBackupDescription, fullBackup => 0) ;

  my $fullBackupDescription = 'test full backup for detail test';
  my $fullBackup = EBox::Backup->makeBackup(description => $fullBackupDescription, fullBackup => 1);

  my $bugreportBackupDescription = 'Bug report'; # string foun in EBox::Backup::makeBugReport
  my $bugreportBackup = EBox::Backup->makeBugReport();

  # XXX date detail IS NOT checked
  my %detailsExpectedByFile = (
			 $configurationBackup => {
						  description => $configurationBackupDescription,
						  type        => $EBox::Backup::CONFIGURATION_BACKUP_ID,
						 },
			 $fullBackup => {
						  description => $fullBackupDescription,
						  type        => $EBox::Backup::FULL_BACKUP_ID,
						 },
			 $bugreportBackup => {
						  description => $bugreportBackupDescription,
						  type        => $EBox::Backup::BUGREPORT_BACKUP_ID,
						 },
			);

  foreach my $file (keys %detailsExpectedByFile) {
    my $details_r;
    lives_ok { $details_r = EBox::Backup->backupDetailsFromArchive($file)  } 'Getting details from file';
    
    my $detailsExpected_r = $detailsExpectedByFile{$file};
    while (my ($detail, $value) = each %{ $detailsExpected_r }) {
      is $details_r->{$detail}, $value, "Checking value of backup detail $detail";
    }
  }
}



sub backupForbiddenWithChangesTest : Test(8)
{
  my ($self) = @_;

  setCanaries('beforeBackup');
  throws_ok {
    my $b = new EBox::Backup;
    $b->makeBackup(description => 'test');
  }  qr/not saved changes/, 'Checkign wether the backup is forbidden with changed modules';


  checkCanaries('beforeBackup', 1);
  checkModulesChanged(named => 'Check wether module changed state has not be changed');
}


sub restoreFailedTest : Test(9)
{
  my ($self) = @_;

  # we force failure in one of the modules
  my $forcedFailureMsg  = 'forced failure ';
  fakeEBoxModule(
		 name => 'canaryMixedConf',
		 subs => [
			  restoreConfig => sub {
			    die $forcedFailureMsg;
			  },
			 ],
		);

  my $global = EBox::Global->getInstance();


  setCanaries('beforeBackup');
  my $backupArchive = checkMakeBackup();

  setCanaries('afterBackup');

  $global->saveAllModules();
  foreach my $mod (@{ $global->modInstances }) {
    $mod->setAsChanged();   # we mark modules as changed to be able to detect
                            # revoked modules
  }

  throws_ok {   
    my $b = new EBox::Backup;
    $b->restoreBackup($backupArchive);

  } qr /$forcedFailureMsg/, 
    'Checking wether restore failed as expected';

  checkCanaries('afterBackup', 1);


  my @modules =  @{ $global->modNames() };
  my @modulesNotChanged =  grep {  (not $global->modIsChanged($_)) } @modules;

  ok scalar @modulesNotChanged > 0, 'Checking wether after the restore failure' . 
  ' some  modules not longer a changed state (this is a clue of revokation)' ;

  setupMixedConfCanary();
}



1;
