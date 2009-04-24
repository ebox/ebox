# Copyright (C) 2009 EBox Technologies S.L.
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
use strict;
use warnings;


package EBox::Squid::Model::DomainFilterFilesBase::Test;
use base 'EBox::Test::Class';

use Test::MockObject::Extends;
use Test::Exception;
use Test::File;
use File::Basename;
use English qw(-no_match_vars);

use lib '../../../..';

use EBox::Squid;
use EBox::Squid::Model::DomainFilterFilesBase;

sub dumpAndRestoreConfigTest : Test(11)
{
    my ($self) = @_;

    my $backupDir = '/tmp/domainfilterfilesbase.test.bdir';
    system "rm -rf $backupDir";
    system "mkdir -p $backupDir";

    my $filterFiles = $self->_newInstance();
    
    lives_ok {
        $filterFiles->dumpConfig($backupDir);
    } 'backing up a empty model';

    lives_ok {
        $filterFiles->restoreConfig($backupDir);
        $filterFiles->setupArchives();
        $filterFiles->cleanOrphanedFiles();
        $filterFiles->cleanEmptyDirs();
    } 'restoring up a empty model';

    my $dir = $filterFiles->listFileDir();
    my $shallalist = '../DomainFilterFilesBase/testdata/shallalist.tar.gz';
    my @filesToSave = ("$dir/save1", "$dir/save2", );
    my @filesToNotSave = ("$dir/noSave1", "$dir/noSave2");
    foreach my $file (@filesToNotSave) {
        system "echo 'content for noSAve $file' > $file";
    }

    foreach my $file (@filesToSave) {
        my $id = basename($file);
        my $uploadFile = "$backupDir/upload";
        system "cp $shallalist $uploadFile";
        system "cp $shallalist $file";

        $filterFiles->addRow(
            description => $id,
            fileList     => $uploadFile,
            id          => $id,
           );
    }
    

    lives_ok {
        $filterFiles->dumpConfig($backupDir);
    } 'backing up a  model';

    # remove fiels that shoudnt be restored
    system "rm @filesToNotSave";

    # mess a little with the files
    
    my $fileDeleted = "$dir/archives/save1/BL/dynamic/domains";
    my $dirThatMustNotExist =  "$dir/archives/mustNotExist";

    system "mv $dir/archives/save2 $dirThatMustNotExist";
    system "rm $fileDeleted";

    lives_ok {
        $filterFiles->restoreConfig($backupDir);
        $filterFiles->setupArchives();
        $filterFiles->cleanOrphanedFiles();
        $filterFiles->cleanEmptyDirs();
    } 'restoring up a  model';

    foreach my $file  (@filesToSave) {
        file_exists_ok($file, "Checking that file was correctly restored");
    }

    my @someFilesInLists = (
        "$dir/archives/save2/BL/politics/urls",
        $fileDeleted,
       );


    foreach my $file  (@someFilesInLists) {
        file_exists_ok($file, "Checking that file was correctly extracted");
    }

    file_not_exists_ok ($dirThatMustNotExist,
        'Checking that superfluous directoy has been deleted');

    foreach my $file  (@filesToNotSave) {
        file_not_exists_ok($file, 
      "Checking that files in the direcory but not in the model were not restored"
                          );
    }

    
}


sub orphanTest
{
# XXX TODO
}


sub startupModules : Test(startup)
{
    EBox::TestStubs::fakeEBoxModule(
        name => 'squid',
        package => 'EBox::Squid',
       );
}

sub startupDirectories : Test(startup)
{
    EBox::TestStubs::setEBoxConfigKeys('tmp' => '/tmp');
}

sub setupListFileDir : Test(setup)
{
    my ($self) = @_;
    my $dir = $self->_listFileDir();
    system "rm -rf $dir";
    system "mkdir -p $dir";
}



sub _newInstance
{
    my ($self) = @_;
    
    my $squid = EBox::Squid->_create();

    my $base = EBox::Squid::Model::DomainFilterFilesBase->new(gconfmodule => $squid,
                                                              directory => 'DomainFilterFilesBaseTest',
                                                             );

    my $instance = Test::MockObject::Extends->new($base);
    $instance->mock('listFileDir', \&_listFileDir);
    $instance->mock('_table', \&_table);
    $instance->mock('_archiveFilesOwner', sub { 
                        my ($gid) = split '\s', $GID;
                        return "$UID.$gid" 
                       } 
         );

#     $instance->mock('categoryForeignModel' => \&_categoryForeignModel);
#     $instance->mock('categoryForeignModelView' => \&_categoryForeignModelView);
#     $instance->mock('categoryBackView' => &_categoryBackView);

    return $instance;

}




sub _listFileDir
{
    return '/tmp/DomainFilterFilesBase.test';
}

sub _table
  {
      my ($self) = @_;
      my $tableHeader = EBox::Squid::Model::DomainFilterFilesBase->_tableHeader();
      my $dataTable =
      {
          tableName          => 'TestDomainFilterFilesBase',
          printableTableName => 'Domains lists files',
          modelDomain        => 'Squid',
          'defaultController' => '/ebox/Squid/Controller/DomainFilterFiles',
          'defaultActions' =>
              [	
              'add', 'del',
              'editField',
              'changeView'
              ],
          tableDescription   => $tableHeader,
          class              => 'dataTable',
          order              => 0,
          rowUnique          => 1,
          printableRowName   => 'internet domain list',
          help               => 'You can uplaod fiels whith list of domains',
          messages           => {
                                  add => 'Domain list added',
                                  del => 'Domain list removed',
                                  update => 'Domain list updated',

                                },
          sortedBy           => 'description',
      };

  }


sub EBox::Squid::Model::DomainFilterFilesBase::_rmAllFilterFiles
{
    system "rm -rf /tmp/DomainFilterFilesBase.test/*";
}

sub EBox::Squid::Model::DomainFilterFilesBase::categoryForeignModel
{
    return 'DomainFilterCategories';
}

sub EBox::Squid::Model::DomainFilterFilesBase::categoryForeignModelView
{
    return '/ebox/Squid/View/DomainFilterCategories';
}


sub EBox::Squid::Model::DomainFilterFilesBase::categoryBackView
{
    return '/ebox/Squid/Composite/FilterSettings';
}



sub EBox::Types::Abstract::setRow
{
    my ($self, $row) = @_;
    $self->{'row'} = $row;
}


1;
