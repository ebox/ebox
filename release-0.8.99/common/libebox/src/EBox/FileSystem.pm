package EBox::FileSystem;
use strict;
use warnings;


use base 'Exporter';
our @EXPORT_OK = qw(makePrivateDir cleanDir isSubdir);

use Params::Validate;
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
  validate_pos(@_, 1);

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

# Function: cleanDir
#       take action to assure that one or more directory have not any file into them. To achieve this files may be delted or directories created
#   		
# Parameters:
#      @dirs - list of directories

sub cleanDir
{
  my @dirs = @_;
  if (@dirs == 0) {
    throw EBox::Exceptions::Internal('cleanDir must be supplied at least a dir as parameter');
  }

  EBox::Validate::checkFilePath($_, 'directory')  foreach  (@dirs);  

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

# Function: isSubdir
#   find if a directory is a sub dir of another. A directory is always a subdirectory of itself
#   		
# Parameters:
#    $subDir - the directory wich we want found if it is a sub directory. It must be a abolute path 
#    $parentDir - the possible parent directory
#
# Returns:
#	wether the first directory is a subdirectory of the second or not
# 
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

# Function: permissionsFromStat
#     examines a File::stat  result object and extract the permissions value
#   		
# Parameters:
#      $stat - stat result object
#
# Returns:
#	the permissions as string
# 
sub permissionsFromStat
{
  my ($stat) = @_;
  return sprintf("%04o", $stat->mode & 07777); 
}


1;
