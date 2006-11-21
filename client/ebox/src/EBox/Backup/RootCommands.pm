package EBox::Backup::RootCommands;
# Provides the root commands used for the backup subsystem
# With the changes in sudoers this has lost sense and we may change this in the fuutres
use strict;
use warnings;
use EBox::Config;
use EBox::Gettext;
use EBox::Sudo;

use Readonly;
Readonly::Scalar our $CDRECORD_PATH=>'/usr/bin/cdrecord';
Readonly::Scalar our $CDRDAO_PATH=>'/usr/bin/cdrdao';
Readonly::Scalar our $MKISOFS_PATH=>'/usr/bin/mkisofs';
Readonly::Scalar our $DVDRWFORMAT_PATH=>'/usr/bin/dvd+rw-format';
Readonly::Scalar our $DVDMEDIAINFO_PATH => '/usr/bin/dvd+rw-mediainfo';
Readonly::Scalar our $EJECT_PATH  => '/usr/bin/eject';
Readonly::Scalar our $GROWISOFS_PATH=>EBox::Config->libexec() . 'growisofs-sudo';

sub checkExecutable
{
  my ($execPath, $program) = @_;
  defined $program or $program = $execPath;

  if (not EBox::Sudo::fileTest('-x', $execPath) ) {
    EBox::error("Cannot found or is not executable: $execPath");
    throw EBox::Exceptions::External(__x('This system need {program} installed to perform the requested action. Please install it and retry', program => $program));
  }  
}

1;
