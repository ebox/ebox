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

package EBox::CGI::EBox::ConfirmBackup;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Config;
use EBox::Backup;
use EBox::Gettext;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;
use Error qw(:try);

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Configuration backups'),
				      'template' => '/confirm-backup.mas',
				      @_);
	bless($self, $class);

	$self->{errorchain} = "EBox/Backup";

	return $self;
}


sub requiredParameters
{
  my ($self) = @_;
  
  if ($self->param('download')) {
    return [qw(download id download.x download.y)];
  }
  elsif ($self->param('delete')) {
    return [qw(delete id delete.x delete.y)];
  }
  elsif ($self->param('burn')) {
    return [qw(burn burn.x burn.y id)]; 
  } 
  elsif ($self->param('restoreFromId')) {
    return [qw(restoreFromId restoreFromId.x restoreFromId.y id)]; 
  }
  elsif ($self->param('restoreFromDisc')) {
    return [qw(restoreFromDisc)];
  } 
  elsif ($self->param('restoreFromFile')) {
    return [qw(restoreFromFile backupfile)];
  }

  return [];
}


sub actuate
{
  my ($self) = @_;

  if (defined($self->param('download'))) {
    $self->{chain} = 'EBox/Backup';
    return;
  }

  foreach my $actionParam (qw(delete burn restoreFromId restoreFromDisc restoreFromFile )) {
    if ($self->param($actionParam)) {
      my $actionSub = $self->can($actionParam . 'Action');
      my ($backupAction, $backupActionText, $backupDetails) = $actionSub->($self);
      $self->{params} = [action => $backupAction, actiontext => $backupActionText, backup => $backupDetails];
      return;
    }
  }


  # otherwise...
  $self->{redirect} = "EBox/Backup";
  return;
}


sub masonParameters
{
  my ($self) = @_;

  if (exists $self->{params}) {
    return $self->{params};
  }

  return [];
}

sub deleteAction
{
  my ($self) = @_;

  $self->{msg} = __('Please confirm that you want to delete the following backup file:');

  return ('delete', __('Delete'), $self->backupDetailsFromId());
}

sub  restoreFromIdAction
{
  my ($self) = @_;

  $self->{msg} = __('Please confirm that you want to restore using this backup file:');

  return ('restoreFromId', __('Restore'), $self->backupDetailsFromId());
} 


sub restoreFromDiscAction
{
  my ($self) = @_;
  
  my $backup = new EBox::Backup;
  my $backupfileInfo = $backup->searchBackupFileInDiscs();
  defined $backupfileInfo or throw EBox::Exceptions::External(__('Unable to find a correct backup disk. Please insert a backup disk and retry')); # XXX TODO: discriminate between no disc and disk with no backup
  
  my $details;

  try {
    $details =  $self->backupDetailsFromFile($backupfileInfo->{file});
  }
  finally {
    $backupfileInfo->{umountSub}->();
  };

  $self->{msg} = __('Please confirm that you want to restore using this backup disk:');
  return ('restoreFromDisc', __('Restore'), $details);
} 


sub  restoreFromFileAction
{
  my ($self) = @_;

  my $filename = $self->upload('backupfile');

  my $details = $self->backupDetailsFromFile($filename);

  $self->{msg} = __('Please confirm that you want to restore using this backup file:');

  return ('restoreFromFile', __('Restore'), $details);
} 


sub  burnAction
{
  my ($self) = @_;

  $self->{msg} = __('Please confirm that you want to write this backup file to a CD or DVD disk:');

  return ('writeBackupToDisc', __('Write to disk'), $self->backupDetailsFromId());
} 


sub backupDetailsFromId
{
  my ($self) = @_;
  my $backup = new EBox::Backup;

  my $id = $self->param('id');
  if ($id =~ m{[./]}) {
    throw EBox::Exceptions::External(
				     __("The input contains invalid characters"));
  }

  my $details =  $backup->backupDetails($id);
  $self->setPrintabletype($details);

  return $details;
}


sub backupDetailsFromFile
{
  my ($self, $filename) = @_;
  my $details = EBox::Backup->backupDetailsFromArchive($filename);

  $self->setPrintabletype($details);

  return $details;
}


sub setPrintabletype
{
  my ($self, $details_r) = @_;

  my $type = $details_r->{type};
  my $printableType;

  if ($type eq $EBox::Backup::CONFIGURATION_BACKUP_ID) {
    $printableType = __('Configuration backup');
  }
  elsif ($type eq $EBox::Backup::FULL_BACKUP_ID) {
    $printableType = __('Full data and configuration backup');
  }  
  elsif ($type eq $EBox::Backup::BUGREPORT_BACKUP_ID) {
    $printableType = __('Bug-report configuration dump');
  }  


  $details_r->{printableType} = $printableType;
  return $details_r;
}


1;
