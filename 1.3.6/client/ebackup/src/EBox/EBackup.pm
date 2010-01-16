# Copyright (C) 2008 eBox Technologies S.L.
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


package EBox::EBackup;

# Class: EBox::EBackup
#
#

use base qw(EBox::Module::Service EBox::Model::ModelProvider
            EBox::Model::CompositeProvider);

use strict;
use warnings;

use EBox::Gettext;
use EBox::Global;
use EBox::Sudo;
use File::Slurp;

use String::ShellQuote;
use Error qw(:try);

use constant DFLTPATH         => '/mnt/backup';
use constant DFLTDIR          => 'ebox-backup';
use constant DFLTKEEP         => '90';
use constant SLBACKUPCONFFILE => '/etc/slbackup/slbackup.conf';

# Constructor: _create
#
#      Create a new EBox::EBackup module object
#
# Returns:
#
#      <EBox::EBackup> - the recently created model
#
sub _create
{
    my $class = shift;

    my $self = $class->SUPER::_create(name => 'ebackup',
            printableName => __('Backup'),
            domain => 'ebox-ebackup',
            @_);

    bless($self, $class);
    return $self;
}


# Method: modelClasses
#
# Overrides:
#
#      <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
        'EBox::EBackup::Model::Local',
        'EBox::EBackup::Model::RemoteSettings',
        'EBox::EBackup::Model::RemoteExcludes',
        'EBox::EBackup::Model::RemoteStatus',
        'EBox::EBackup::Model::RemoteFileList',
    ];
}


# Method: compositeClasses
#
# Overrides:
#
#      <EBox::Model::CompositeProvider::compositeClasses>
#
sub compositeClasses
{
    return [
        'EBox::EBackup::Composite::General',
        'EBox::EBackup::Composite::RemoteGeneral',
        'EBox::EBackup::Composite::Remote',
    ];
}


# Method: actions
#
# Overrides:
#
#      <EBox::Module::Service::actions>
#
sub actions
{
    return [
    {
        'action' => __('Install /etc/cron.daily/ebox-ebackup-cron.'),
        'reason' => __('eBox will run a nightly script to backup your system.'),
        'module' => 'ebackup'
    },
    ];
}


# Method: usedFiles
#
# Overrides:
#
#      <EBox::ServiceModule::ServiceInterface::usedFiles>
#
#sub usedFiles
#{
#    my @usedFiles;
#
#    push (@usedFiles, { 'file' => SLBACKUPCONFFILE,
#                        'module' => 'ebackup',
#                        'reason' => __('To configure backups.')
#                      });
#
#    return \@usedFiles;
#}

# Method: remoteArguments
#
#   Return the arguments to be used by duplicty
#
# Arguments:
#
#       type - full or incremental
#
# Returns:
#
#   String contaning the arguments for duplicy
sub remoteArguments
{
    my ($self, $type) = @_;

    my $model = $self->model('RemoteExcludes');
    my $excludes = '';
    my $includes = '';
    my $regexps = '';
    for my $id (@{$model->ids()}) {
        my $row = $model->row($id);
        if ($row->valueByName('type') eq 'exclude_path') {
            my $path = shell_quote($row->valueByName('target'));
            $excludes .= "--exclude=$path ";
        } elsif ($row->valueByName('type') eq 'include_path') {
            my $path = shell_quote($row->valueByName('target'));
            $includes .= "--include=$path ";
        } else {
            my $regexp = $row->valueByName('target');
            $regexps .= "--exclude-regexp $regexp";
        }
    }

    my $pass = $self->model('RemoteSettings')->row()->valueByName('password');
    return "FTP_PASSWORD='$pass' duplicity $type "
           . "$includes $excludes $regexps / " . $self->_remoteUrl();
}

# Method: remoteDelOldArguments
#
#   Return the arguments to be used by duplicty to delete old files
#
# Returns:
#
#   String contaning the arguments for duplicy
sub remoteDelOldArguments
{
    my ($self, $type) = @_;

    my $model = $self->model('RemoteSettings');
    my $toKeep = $model->row()->valueByName('full_copies_to_keep');
    my $freq = $model->row()->valueByName('full');
    my $time = uc(substr($freq, 0, 1));
    my $pass = $model->row()->valueByName('password');

    return "FTP_PASSWORD='$pass' duplicity remove-older-than ${toKeep}${time} " . $self->_remoteUrl();
}

# Method: remoteListFileArguments
#
#   Return the arguments to be used by duplicty to list remote files
#
# Returns:
#
#   String contaning the arguments for duplicity
#
sub remoteListFileArguments
{
    my ($self, $type) = @_;

    my $model = $self->model('RemoteSettings');
    my $pass = $model->row()->valueByName('password');

    return "FTP_PASSWORD='$pass' duplicity list-current-files " . $self->_remoteUrl();
}



sub remoteStatus
{
    my ($self) = @_;

    my $storedTime = $self->{remoteCacheTime};
    if ($storedTime and ($storedTime + 1000 > time())) {
        return $self->{remoteCache};
    }

    my @status;
    if (-f tmpCurrentStatus()) {
        my @lines = File::Slurp::read_file(tmpCurrentStatus());
        for my $line (@lines) {
            # We are trying to match this:
            #  Full Wed Sep 23 13:30:56 2009 95
            #  Incr Fri Sep 23 13:30:56 2009 95
            my $regexp = '^\s+(\w+)\s+(\w+\s+\w+\s+\d\d? '
                    . '\d\d:\d\d:\d\d \d{4})\s+\d+';
            if ($line =~ /$regexp/ ) {
                push (@status, {
                        type => $1,
                        date => $2 }
                     );
            }
        }
    }

    $self->{remoteCacheTime} = time();
    $self->{remoteCache} = \@status;

    return \@status;
}

sub tmpCurrentStatus
{
    return EBox::Config::tmp() . "backupstatus-cache";
}

sub remoteGenerateStatusCache
{
    my ($self) = @_;

    my $file = tmpCurrentStatus();
    my $remoteUrl = $self->_remoteUrl();
    my $password = $self->model('RemoteSettings')->row()->valueByName('password');
    my $cmd = "FTP_PASSWORD='$password' duplicity collection-status $remoteUrl";
    try {
        File::Slurp::write_file($file, @{EBox::Sudo::root($cmd)});
    } otherwise {};
}

sub tmpFileList
{
    return EBox::Config::tmp() . "backuplist-cache";
}

sub remoteListFiles
{
    my ($self) = @_;

    my $file = tmpFileList();
    return [] unless (-f $file);

    unless ($self->{files}) {
    my @files;
    for my $line (File::Slurp::read_file($file)) {
        my $regexp = '^\s*(\w+\s+\w+\s+\d\d? '
                . '\d\d:\d\d:\d\d \d{4} )(.*)';
        if ($line =~ /$regexp/ ) {
            push (@files, "/$2");
        }
    }
        $self->{files} = \@files;
    }
    return $self->{files};
}

sub setRemoteBackupCrontab
{
    my ($self) = @_;

    my @lines;
    my $strings = $self->model('RemoteSettings')->crontabStrings();
    my $full = $strings->{full};
    my $incr = $strings->{incremental};
    my $script = EBox::Config::share() . 'ebox-ebackup/ebox-remote-ebackup';
    push (@lines, "$full $script --full");
    if ($incr) {
        push (@lines, "$incr $script --incremental");
    }
    my $tmpFile = EBox::Config::tmp() . 'crontab';
    open(my $tmp, '>' .  EBox::Config::tmp() . 'crontab');
    if ($self->isEnabled()) {
        for my $line (@lines) {
            print $tmp "$line\n";
        }
    }
    close($tmp);
    EBox::Sudo::command("crontab $tmpFile");
}

# Method: _setConf
#
# Overrides:
#
#      <EBox::Module::Service::_setConf>
#
sub _setConf
{
    my ($self) = @_;
    # install cronjob
    my $cronFile = EBox::Config::share() . '/ebox-ebackup/ebox-ebackup-cron';
    EBox::Sudo::root("install -m 0755 -o root -g root $cronFile /etc/cron.daily/");
    $self->setRemoteBackupCrontab();
}


# Method: _setSLBackup
#FIXME doc
#sub _setSLBackup
#{
#    my ($self) = @_;
#
#    my $model = $self->model('Hosts');
#
#    my @hosts = ();
#    foreach my $host (@{$model->ids()}) {
#        my $row = $model->row($host);
#        my $hostname = $row->valueByName('hostname');
#        my $keep = $row->valueByName('keep');
#        push (@hosts, { hostname => $hostname,
#                        keep => $keep,
#                      });
#    }
#
#    $model = $self->model('Settings');
#
#    my $backuppath = $model->backupPathValue();
#
#    my @params = ();
#
#    #push (@params, hosts => \@hosts );
#    push (@params, backuppath => $backuppath);
#
#    $self->writeConfFile(SLBACKUPCONFFILE, "ebackup/slbackup.conf.mas", \@params,
#                            { 'uid' => 0, 'gid' => 0, mode => '640' });
#}


# Method: menu
#
# Overrides:
#
#      <EBox::Module::menu>
#
sub menu
{
    my ($self, $root) = @_;

    $root->add(new EBox::Menu::Item(
            'url' => 'EBackup/Composite/Remote',
            'separator' => 'Core',
            'order' => 95,
            'text' => $self->printableName()));
}

sub _remoteUrl
{
    my ($self) = @_;

    my $user;
    my $password;

    my $model = $self->model('RemoteSettings');
    my $method = $model->row()->valueByName('method');
    my $target = $model->row()->valueByName('target');
    my $url = "$method://";
    if ($method ne 'file') {
        $user = $model->row()->valueByName('user');
        if ($user) {
            $url .= "$user@";
        }
    }

    $url .= $target;

    if ($method eq 'scp') {
        $url .= ' --ssh-askpass';
    }

    my $gpgKey = $model->row()->valueByName('gpg_key');
    if ($gpgKey eq 'disabled') {
        $url .= ' --no-encryption';
    } else {
        $url .= " --encrypt-key $gpgKey";
    }

    return $url;
}

1;