package EBox::FileSystem;
use strict;
use warnings;


use base 'Exporter';
our @EXPORT_OK = qw(makePrivateDir cleanDir isSubdir);

use EBox::Validate;

# Method: makePrivateDir
#
#	Creates  a  directory owned by the user running this
#	process and with private permissions.
#
# Parameters:
#
#	path - The path of the directory to be created, if it exists it must
#	       already have proper ownership and permissions.
#
# Exceptions:
#
#	Internal & External - The path exists and is not a directory or has wrong
#		   ownership or permissions. Or it does not exist and 
#		   cannot be created.
sub makePrivateDir # (path)
{
  my ($dir) = @_;


  if (-e $dir) {
    if (  not -d $dir) {
      throw EBox::Exceptions::Internal( "Cannot create private directory $dir: file exists");
    } 
    else {
      return EBox::Validate::isPrivateDir($dir, 1);
    }
  }

  mkdir($dir, 0700) or throw EBox::Exceptions::Internal("Could not create directory: $dir");

}

sub cleanDir
{
  my @dirs = @_;

  foreach my $d (@dirs) {
    my $dir;
    my $mode = 0700;

    if (ref $d eq 'HASH' ) {
      $dir  = $d->{name};
      $mode = $d->{mode}
    }
    else {
      $dir = $d;
    }

    if ( -e $dir) {
      if (! -d $dir) {
	throw EBox::Exceptions::Internal("$dir exists and is not a directory");
      }

      system "rm -rf $dir/*";
      if ($? != 0) {
	throw EBox::Exceptions::Internal "Error cleaning $dir: $!";
      }
    } 
    else {
      mkdir ($dir, $mode) or  throw EBox::Exceptions::Internal("Could not create directory: $dir");      
    }

  }
}


sub isSubdir
{
  my ($subDir, $parentDir) = @_;

  foreach ($subDir, $parentDir) {
    if (! EBox::Validate::checkAbsoluteFilePath($_)) {
      throw EBox::Exceptions::Internal("isSubdir can only called with absolute paths. Argumentes were ($subDir, $parentDir)))");
    } 
  }


  # normalize paths
  $subDir .= '/';
  $parentDir .= '/';
  $subDir =~ s{/+}{/}g;
  $parentDir =~ s{/+}{/}g;

  return $subDir =~ m/^$parentDir/;
  
}

sub permissionsFromStat
{
  my ($stat) = @_;
  return sprintf("%04o", $st->mode & 07777); 
}


1;
