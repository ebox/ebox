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

package EBox::Sudo;

use strict;
use warnings;

use EBox::Config;
use EBox::Exceptions::Internal;
use EBox::Gettext;
use File::stat qw();
use File::Slurp;
use Error qw(:try);
use Params::Validate;
use Perl6::Junction;

use EBox::Exceptions::Sudo::Command;
use EBox::Exceptions::Sudo::Wrapper;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS  = (all => [qw{ root command stat rootCommandForStat} ],
			);
	@EXPORT_OK = qw();;

	Exporter::export_ok_tags('all');
	$VERSION = EBox::Config::version;
}


use Readonly;
Readonly::Scalar our $SUDO_PATH   => '/usr/bin/sudo -p sudo:'; # our declaration eases testing
Readonly::Scalar our  $STDERR_FILE =>  EBox::Config::tmp() . 'stderr';

Readonly::Scalar my $STAT_CMD => '/usr/bin/stat -cSTI%dI%iI%fI%hI%uI%gIhI%sI%XI%YI%ZI%oI%bI%tI%T';
Readonly::Scalar my  $TEST_PATH   => '/usr/bin/test';
#
# Procedure: command 
#
#	Executes a command as ebox user 
#
# Parameters:
#
#       command - string with the command to execute
#
#
# Exceptions:
#
#       Internal  - If command fails
#
# Returns:
# 	array ref - Returns the output of the command in an array
#
sub command # (command) 
{
  my ($cmd) = @_;
  validate_pos(@_, 1);

  my @output = `$cmd`;
  if ($? != 0) {
    throw EBox::Exceptions::Internal(
				     __x("Command '{cmd}' failed. Output: {output}", cmd => $cmd, output => join "\n", @output));
  }

  return \@output;
}

#
# Procedure: root 
#
#	Executes a command through sudo. Use this to execute privileged
#	commands. 
#
# Parameters:
#
#       command - string with the command to execute
#
#
# Exceptions:
#
#       Internal  - If command fails
#
# Returns:
# 	array ref - Returns the output of the command in an array
sub root # (command) 
{
  my ($cmd) = @_;
  validate_pos(@_, 1);

  my $sudocmd = "$SUDO_PATH $cmd 2> $STDERR_FILE";

  my @output = `$sudocmd`;

  if ($? != 0) {
    my @error;
    if ( -r $STDERR_FILE) {
      @error = read_file($STDERR_FILE);
    }
	  
    _rootError($sudocmd, $cmd, $?, \@output, \@error);
  } 

  return \@output;
}


sub _rootError
{
  my ($sudocmd, $cmd, $childError, $output, $error) = @_;

  if ($childError == -1) {
    throw EBox::Exceptions::Sudo::Wrapper("Failed to execute $sudocmd");
  }
  elsif ($childError & 127) {
    my $signal = ($childError & 127);
    my $coredump = ($childError & 128) ? 'with coredump' : 'without coredump';
    throw EBox::Exceptions::Sudo::Wrapper("$sudocmd died with signal $signal $coredump");
  } 

  my $exitValue =  $childError >>  8;

  if ($exitValue == 1 ) {	# may be a sudo-program error 
    my $errorText =  join "\n", @{$error};


    if ($errorText =~ m/^sudo:/m) {
      throw EBox::Exceptions::Sudo::Wrapper("$sudocmd raised the following sudo error: $errorText");
    }
    elsif ($errorText =~ m/is not in the sudoers file/m) {
      throw EBox::Exceptions::Sudo::Wrapper("$sudocmd failed because either the current user (EUID $>) is not in sudoers files or it has incorrects settings on it. Running ebox-sudoers-friendly maybe can fix this problem");
    } 
  }

  throw EBox::Exceptions::Sudo::Command(cmd => $cmd, output => $output, error => $error,  exitValue => $exitValue)
}

# Procedure: rootWithoutException
#
#	Executes a command through sudo. This version does not raises exception on error level and must be used _only_ if you take responsability to parse the output or use anorther method to determine success status
#
# Parameters:
#
#       command - string with the command to execute
#
# Returns:
# 	array ref - Returns the output of the command in an array
sub rootWithoutException
{
  my ($cmd) = @_;
  validate_pos(@_, 1);

  my $output;
  try {
    $output =  root($cmd);
  }
  catch EBox::Exceptions::Sudo::Command with { # ignore failed commands
    my $ex = shift @_;  
    $output = $ex->output();
  };

  return $output;
}

# 
# Procedure: sudo 
#
#	Executes a command through sudo as a given user. 
#
# Parameters:
#
#       command - string with the command to execute
#	user - user to run the command as
#
#
# Exceptions:
#
#       Internal  - If command fails
#
sub sudo # (command, user) 
{
	my ($cmd, $user) = @_;
	validate_pos(@_, 1 ,1);

	unless (system("$SUDO_PATH -u " . $user . " " . $cmd) == 0) {
		throw EBox::Exceptions::Internal(
			__x("Running command '{cmd}' as {user} failed", 
				cmd => $cmd, user => $user));
	}
}


# Procedure: stat
#   stat a file as root user and returns the information as File::stat object
#   		
# Parameters:
#    $file - file we want stat
#
# Returns:
#	a File::Stat object with the file system status for the file
# 
sub stat
{
  my ($file) = @_;
  validate_pos(@_, 1);
  
  my $statCmd = "$STAT_CMD $file";
  my $statOutput;

  try {
    $statOutput = root($statCmd);
  }
  catch EBox::Exceptions::Sudo::Command with {
    $statOutput = undef;
  };


  return undef if !defined $statOutput;

  my @statElements = split '[I\n]', $statOutput->[0]; # this may cause a warning in implementation of stat. See next comment

  # the stat id is for systems where stat does not return a different exit code when stating a inexistent file
  my $statId = shift @statElements;
  if ($statId ne 'ST') {
    return undef;
  }

  # convert file mode from hexadecimal...
  $statElements[2]  = hex $statElements[2]; 

  # extract minor and major numbers for recereate rdev
  my $minorNumber =  hex (pop @statElements);
  my $majorNumber =  hex (pop @statElements);

  $statElements[6] = _makeRdev($majorNumber, $minorNumber);

  my $statObject = File::stat::populate( @statElements );
  return $statObject;
}


# XXX maybe this should be constants..
my $MAJOR_MASK  = 03777400;         
my $MAJOR_SHIFT = 0000010;          
my $MINOR_MASK  = 037774000377;     
my $MINOR_SHIFT = 0000000;

sub _makeRdev
{
  my ($major, $minor) = @_;
  my $rdev =  (($major << $MAJOR_SHIFT) & $MAJOR_MASK) | (($minor << $MINOR_SHIFT) & $MINOR_MASK);
  return $rdev;
}



my $anyFileTestPredicate = Perl6::Junction::any(qw(-b -c -d -e -f -g -G  -h  -k -L -O -p -r -s -S -t -u -w -x) );

#  Procedure: fileTest
#
#    Do a file test as the root user. Implemented as a wrapper around the test program
#
#  Parameters:
#      $test - the file test. File tests allowed: -b -c -d -e -f -g -G  -h  -k -L -O -p -r -s -S -t -u -w -
#      $file - file to test
#
#   Returns:
#     bool value with the result of the file test
sub fileTest
{
  my ($test, $file) = @_;
  validate_pos(@_, 1, 1);
  
  ($test eq $anyFileTestPredicate) or throw EBox::Exceptions::Internal("Unknown or unsupported test file predicate: $test (upon $file)");

  my $testCmd = "$TEST_PATH $test $file";
  rootWithoutException($testCmd);
  
  return ($? == 0);  # $? was set by execution of $testCmd
}

1;
