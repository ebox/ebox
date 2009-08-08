package EBox::Backup::FileBurner;
# Wrapper for burning methods
use strict;
use warnings;

use EBox;
use EBox::Gettext;
use EBox::Backup::RootCommands;
use EBox::Backup::OpticalDisc;
use EBox::Backup::OpticalDiscDrives;
use Perl6::Junction qw(all any);
use Error qw(:try);
use File::stat;

use Readonly;
Readonly::Scalar my $MTAB_PATH=>'/etc/mtab';

#
# Function: burn
#
#  writes a file in a optical disc. after 
#
# Parameters:
#
#   file - file to write in the disc. Mandatory
#   device - device file of the recorder to use for writing. Optional. If not supplied we will try to choose the recorder available. We use as criteria the number of format the writer can use as proxy for quality
#
sub burn
{
  my %params = @_;
  
  my $file   = $params{file};
  defined $file or throw EBox::Exceptions::MissingArgument('file');
  my $device = exists $params{device} ? $params{device} : _chooseDevice();

  _checkDevice($device);

  my $mediaInfo = EBox::Backup::OpticalDisc::media($device);
  my $media    = $mediaInfo->{media};
  my $writable = $mediaInfo->{writable};

  _checkMedia($media, $writable);
  _checkDeviceForMedia($device, $media);
  _checkSize($file, $media);

  my $target = _setupBurningTarget($file, $media);

  if (_mediaUsesCdrecord($media)) {
    $device = _deviceForCdrecord($device);
  }

  if (!$writable) {
    blankMedia($device, $media, $writable);
  }

  burnMedia($target, $device, $media);

  EBox::Backup::OpticalDiscDrives::ejectDisc($device);
}

#
# Function: burningAvailable
#
#  Check if we have CD/DVD recorders available
#
# Returns:
#        wether burning capabilities are availble or not	
#
#  Limitations:
#     see #158 for possible problems
sub burningAvailable
{
  my %info = %{EBox::Backup::OpticalDiscDrives::info() };
  my $candidate = undef;
  my $maxScore = 0;
  my @writingMedia = qw(CD-R CD-RW DVD-R);

  while (my $capabilities_r = values %info) {
    foreach my $capability (@writingMedia) {
      $capability = 'Can write ' . $capability;
      return 1 if ($capabilities_r->{$capability});
    }
  }

  return 0;
}

# the device choosed with the criterium of number of formats that it can write
# we also check for formats that we do not use becuase it may be a porxy for quality (and we are not be able to recognize dvd-rw capabilities see #158)
sub _chooseDevice
{
  my %info = %{EBox::Backup::OpticalDiscDrives::info() };
  my $candidate = undef;
  my $maxScore = 0;
  my @writingMedia = qw(CD-R CD-RW DVD-R DVD-RAM MRW RAM);

  while (my($dev, $capabilities_r) = each %info) {
    my $score = 0;
    foreach my $capability (@writingMedia) {
      $capability = 'Can write ' . $capability;
      $score += 1 if ($capabilities_r->{$capability});
    }
    if ($score > $maxScore) {
      $maxScore = $score;
      $candidate = $dev;
    }
  }

  if (!defined $candidate) {
    throw EBox::Exceptions::External(__('This system does not have a recorder drive'));
  }
  
  return $candidate;
}


sub _checkMedia
{
  my ($media, $writable) = @_;

  if ($media eq 'no_disc') {
      throw EBox::Exceptions::External(__('No disk found. Please insert disk and retry'));
  }

  if ($media eq 'DVD-ROM') {
    throw EBox::Exceptions::External('DVD-ROM cannot be written. Instead use a DVD-R or DVD-RW');
  }

  if ($media ne all(qw(CD-R CD-RW DVD-R DVD-RW))) {
    throw EBox::Exceptions::External(__x('{media } is a unsupported media type'), media => $media)
  }

  if (not $writable) {
    _mediaIsRewritable($media) or throw EBox::Exceptions::External('Disk is full. Please retry with a blank disk');
  }

}

sub _checkDevice
{
  my ($device) = @_;

  if (!-e $device) {
    throw EBox::Exceptions::External(__x('{device} cannot be found', device => $device))
  }


  open my $MTAB, "<$MTAB_PATH";
  try {
    while (my $line = <$MTAB>) {
       my ($mountedDev) = split '\s+', $line, 2;
       if ($mountedDev eq $device) {
	 throw EBox::Exceptions::External(__x('{device} is mounted. Please, remove the disk', device => $device))    
       }
    }
  }
  finally {
    close $MTAB;
  };
  

}

sub _checkDeviceForMedia
{
  my ($device, $media) = @_;



  my $normalizedMedia = $media;
  $normalizedMedia =~ s/-//;

  my $writersForMediaSub = EBox::Backup::OpticalDiscDrives->can("writersFor$normalizedMedia");
  defined $writersForMediaSub or throw EBox::Exceptions::Internal("'$media' is a unknown or non supported media type");
  my @writersForMedia = $writersForMediaSub->();
  if ($device ne all(@writersForMedia)) {
    throw EBox::Exceptions::External(__x('Device {dev} cannot write media of type {media}', dev => $device, media => $media));
  }

}

sub _checkSize
{
  my ($file, $media) = @_;
  my $st = stat($file) ;
  defined $st or throw EBox::Exceptions::Internal("Cannot stat $file");

  my $size = $st->size();
  my $mediaSize = EBox::Backup::OpticalDisc::sizeForMedia($media);

  if ($size >= $mediaSize) {
    throw EBox::Exceptions::External(__('The media has not sufficient capabilty for the data'));
  }
}
 

sub _mediaUsesCdrecord
{
  my ($media) = @_;
  return $media eq  any('CD-R', 'CD-RW');
}

sub _mediaUsesGrowisofs
{
  my ($media) = @_;
  return $media eq  any('DVD-R', 'DVD-RW');
}

sub _mediaIsRewritable
{
  my ($media) = @_;
  return $media eq  any('CD-RW', 'DVD-RW');
}

sub _setupBurningTarget
{
  my ($file, $media) = @_;

  if ( _mediaUsesCdrecord($media) ) {
    EBox::Backup::RootCommands::checkExecutable($EBox::Backup::RootCommands::MKISOFS_PATH, 'mkisofs');

    my $isoFile = EBox::Config::tmp() . 'backup.iso';
    my $mkisofsCommand = "$EBox::Backup::RootCommands::MKISOFS_PATH -V ebox-backup  -R -J  -o $isoFile $file";
    EBox::Sudo::command($mkisofsCommand);
    return $isoFile;
  }
  elsif ( _mediaUsesGrowisofs($media) ) {
    return $file;
  }
  else {
    throw EBox::Exceptions::Internal("No setup burning target provided for media $media");
  }
  
}


# this is for cdrecord device nightmare..
sub _deviceForCdrecord
{
  my ($device) = @_;

  # XXX Only IDE devices uspported for now!
# proposar to parse cdrecord:
#   my @output = EBox::Sudo::root("$CDRECORD_PATH -scanbus");
#     return $device if grep { !($_ =~ /\d) \*/ } @output;

  EBox::Backup::RootCommands::checkExecutable($EBox::Backup::RootCommands::CDRECORD_PATH, 'cdrecord');
  my  @output = EBox::Sudo::root("$EBox::Backup::RootCommands::CDRECORD_PATH dev=ATA: -scanbus");
  my $ideDevicesFound = grep { !($_ =~ /\d\) \*/) } @output;
  if (0 == $ideDevicesFound) {
    throw EBox::Exceptions::Internal("Cannot found the device identified for cdrecord");
  }

  return $device;
}

#
# Function: blankMedia
#
#   	blanks the optical media	
#
# Parameters:
#
#  $device - device file of the recorder drive
#  $media  - media type of the will-be blanked disc
#
sub blankMedia
{
  my ($device, $media) = @_;

  my $command;
  if ($media eq  'CD-RW') {
    EBox::Backup::RootCommands::checkExecutable($EBox::Backup::RootCommands::CDRECORD_PATH, 'cdrecord');

    $command = "$EBox::Backup::RootCommands::CDRECORD_PATH dev=$device --gracetime=2  -tao  blank=fast";
  }
  elsif ($media eq 'DVD-RW') {
    EBox::Backup::RootCommands::checkExecutable($EBox::Backup::RootCommands::DVDRWFORMAT_PATH, 'dvd+rw tools');

    $command = "$EBox::Backup::RootCommands::DVDRWFORMAT_PATH -blank $device";
  }

  (defined $command) or throw EBox::Exceptions::External(__x('No blanking method for {media}  defined. Cannot erase it', media => $media));

  EBox::info("Blanking media in $device");
  EBox::Sudo::root($command);
}

#
# Function: burnMedia
#
#   begins the burning process	
#
# Parameters:
#
#  $device - device file of the recorder drive
#  $media  - media type of the will-be blanked disc
#  $target - target of the burning process 
#
#
# Limitations:
#	this function is not intended to be called for the user, use burn instead
#
# See also:
#   burn
sub burnMedia
{
  my ($target, $device, $media) = @_;

  my $command;
  if ( _mediaUsesCdrecord($media) ) {
    EBox::Backup::RootCommands::checkExecutable($EBox::Backup::RootCommands::CDRECORD_PATH, 'cdrecord');

    $command = "$EBox::Backup::RootCommands::CDRECORD_PATH dev=$device --gracetime=2 -tao $target";
  }
  elsif ( _mediaUsesGrowisofs($media) ) {
    EBox::Backup::RootCommands::checkExecutable($EBox::Backup::RootCommands::GROWISOFS_PATH, 'growisofs');

     $command = "$EBox::Backup::RootCommands::GROWISOFS_PATH -Z $device -R -J -V ebox-backup $target";
  }
  else {
    throw EBox::Excepions::Internal("No burning commands for media $media");    
  }


  EBox::info("Burning data in $device");
  EBox::debug("Command used: $command");

  EBox::Sudo::root($command);
}




1;
