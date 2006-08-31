package GConfBackupTest;
use base 'Test::Class';

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Gnome2::GConf;

use EBox::TestStub;
use EBox::Config::TestStub;


use Readonly;
Readonly::Scalar my $TEST_DIR => '/tmp/ebox.gconfbackup.test';

use lib '../../..';
use EBox::Backup;

sub fakeEBox : Test(startup)
{
  EBox::TestStub::fake();
  EBox::Config::TestStub::fake(tmp => $TEST_DIR);
}


sub setupTestDir : Test(setup)
{
  system "rm -rf $TEST_DIR";
  mkdir $TEST_DIR;
  mkdir EBox::Backup::backupDir();
}

sub gconfBackupTest : Test(3)
{
  my $canaryKey = '/ebox/before';
  my $backup = EBox::Backup->_create();

  my $client = Gnome2::GConf::Client->get_default;
  $client->set_bool($canaryKey, 1);

  lives_ok { $backup->backupGConf() } "Backing up GConf";

  $client->set_bool($canaryKey, 0);
  if ($client->get_bool($canaryKey)) {
    die "GConf operation failed";
  }

  lives_ok { $backup->restoreGConf() } 'Restoring GConf';
  ok $client->get_bool($canaryKey), 'Checking canary GConf entry after restore';
}

1;
