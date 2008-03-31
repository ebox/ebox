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

package EBox::Software;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::ServiceModule::ServiceInterface);

use EBox;
use EBox::Config;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;
use EBox::Exceptions::MissingArgument;
use EBox::Gettext;
use EBox::Menu::Folder;
use EBox::Menu::Item;
use EBox::ProgressIndicator;
use EBox::Sudo qw( :all );

use Digest::MD5;
use Error qw(:try);
use Storable qw(fd_retrieve store retrieve);
use Fcntl qw(:flock);

# Constants
use constant {
    LOCK_FILE     => EBox::Config::tmp() . 'ebox-software-lock',
    LOCKED_BY_KEY => 'lockedBy',
    LOCKER_PID_KEY => 'lockerPid',
};

# Group: Public methods

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'software', 
						domain => 'ebox-software',
						@_);
	bless($self, $class);
	return $self;
}

# Method: actions
#
# 	Override EBox::ServiceModule::ServiceInterface::actions
#
sub actions
{
  return [ 
	  {
	   'action' => __(q{Add rule to firewall to allow HTTP connections}),
	   'reason' => __(q{eBox needs to access package repositories via HTTP to download packages}),
	   'module' => 'software',
	  },
#	  {
#	   'action' => __(q{Change configuration of dpkg and ucf}),
#	   'reason' => __(q{The new configuration is needed to always preserve old configuration files}),
#	   'module' => 'software',
#	  },
	  {
	   'action' => __(q{Change software packages repositories}),
	   'reason' => __('The software module needs to add custom repositories: '.
                      '{repo}', repo => 
                      'deb http://ppa.launchpad.net/juruen/ubuntu hardy main'),
	   'module' => 'software',
	  },
#	  {
#	   'action' => __(q{Change debconf configuration}),
#	   'reason' => __(q{eBox software module uses non-interactive mode and a critical priority}),
#	   'module' => 'software',
#	  },

	 ];
}


# Method: usedFiles 
#
# 	Override EBox::ServiceModule::ServiceInterface::files
#
sub usedFiles 
{
  my @usedFiles = (
#		   {	
#		    'file' =>   '/etc/dpkg/dpkg.cfg',
#		    'reason' => __(q{To make sure dpkg prefers to preserver old configuration file}),
#		    'module' => 'software'
#		   },
#		   {	
#		    'file' =>   '/etc/ucf.conf',
#		    'reason' => __(q{To make sure ucf prefers to preserver old configuration file}),
#		    'module' => 'software'
#		   },
		   {	
		    'file' =>   '/etc/apt/sources.list',
		    'reason' => __(q{To add custom repositories}),
		    'module' => 'software'
		   },
		  );
 


   return \@usedFiles;
}

# Method: enableActions 
#
# 	Override EBox::ServiceModule::ServiceInterface::enableActions
#
sub enableActions
{
    root(EBox::Config::share() . '/ebox-software/ebox-software-enable');
}

#  Method: serviceModuleName
#
#   Override EBox::ServiceModule::ServiceInterface::serviceModuleName
#
sub serviceModuleName
{
	return 'software';
}

#  Method: enableModDepends
#
#   Override EBox::ServiceModule::ServiceInterface::enableModDepends
#
sub enableModDepends 
{
    return ['network'];
}


# Method: listEBoxPkgs
# 	
# 	Returns an array of hashes with the following fields:
#	name - name of the package
#	description - short description of the package
#	version - version installed (if any)
#	avail - latest version available
#	removable - true if the package can be removed
#
# Returns:
#
# 	array ref of hashes holding the above keys
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub listEBoxPkgs
{
	my ($self,$clear) = @_;

	my $eboxlist = [];

	my $file = EBox::Config::tmp . "eboxpackagelist";

	if(defined($clear) and $clear == 1){
		if ( -f "$file" ) {
			unlink($file);
		}
	}else{
		if (-f "$file" ) {
			$eboxlist = retrieve($file);
			return $eboxlist;
		}
	}

        $self->_isModLocked();
	$eboxlist =  _getInfoEBoxPkgs();

	store($eboxlist, $file);
	return $eboxlist;
}

# Method: installPkgs 
#	
#	Installs a list of packages via apt
# 
# Parameters:
#
# 	array -  holding the package names
#
# Returns:
#
#       <EBox::ProgressIndicator> - an instance of the progress
#       indicator to indicate how the installation is working
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub installPkgs # (@pkgs)
{
	my ($self, @pkgs) = @_;

        $self->_isModLocked();

	if (not @pkgs) {
	  EBox::info("No packages to install");
	  return;
	}

	my $executable = EBox::Config::share() . "/ebox-software/ebox-update-packages @pkgs";
	my $progress = EBox::ProgressIndicator->create(
						       totalTicks => scalar @pkgs,
						       executable => $executable,
						      );
	$progress->runExecutable();
	return $progress;
}

# Method: removePkgs
#
#	Removes a list of packages via apt
#
# Parameters:
#
# 	array -  holding the package names
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub removePkgs # (@pkgs)
{
	my ($self, @pkgs) = @_;

        $self->_isModLocked();

	my $cmd ='/usr/bin/apt-get remove --purge --no-download -q --yes ';
	$cmd .= join(" ", @pkgs);
	try {
		root($cmd);
	} catch EBox::Exceptions::Internal with {
		throw EBox::Exceptions::External(__('An error ocurred while '.
			'removing components. If the error persists or eBox '.
			'stops working properly, seek technical support.'));
	};
}

# Method: updatePkgList
#
#	Update the package list
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub updatePkgList
{
	my ($self) = @_;

        $self->_isModLocked();

	my $cmd ='/usr/bin/apt-get update -qq';
	try {
		root($cmd);
	} catch EBox::Exceptions::Internal with {
	};
}

# Method: fetchAllPkgs 
#	
#	Download all the new ebox packages and the system updates
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub fetchAllPkgs
{
        my ($self) = @_;

        $self->_isModLocked();

	my @pkgs;

	@pkgs = @{_getInfoEBoxPkgs()};

	my $cmd ='/usr/bin/apt-get install -qq --download-only --yes ';
	foreach my $pkg (@pkgs) {
		$cmd .= ($pkg->{name} . " ");
		$cmd .= (join(" ", @{$pkg->{depends}}) . " ");
	}
	try {
		root($cmd);
	} catch EBox::Exceptions::Internal with {
	};

	$cmd ='/usr/bin/apt-get dist-upgrade -qq --download-only --yes';
	try {
		root($cmd);
	} catch EBox::Exceptions::Internal with {
	};

	$cmd ='/usr/bin/apt-get autoclean -qq --yes';
	try {
		root($cmd);
	} catch EBox::Exceptions::Internal with {
	};
}

# Method: listUpgradablePkgs
#	
#	Returns a list of those packages which are ready to be upgraded
#
# Parameters:
#
# 	clear - if set to 1, forces the cache to be cleared
#
# Returns:
#
#	array ref - holding hashes ref containing keys: 'name' and 
#	'description' for each package
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub listUpgradablePkgs 
{
	my ($self,$clear) = @_;

	my $upgrade = [];

	my $file = EBox::Config::tmp . "packagelist";

	if(defined($clear) and $clear == 1){
		if ( -f "$file" ) {
			unlink($file);
		}
	}else{
		if (-f "$file" ) {
			$upgrade = retrieve($file);
			return $upgrade;
		}
	}

        $self->_isModLocked();

	$upgrade = _getUpgradablePkgs();

	store($upgrade, $file);
	return $upgrade;
}

# Method: listPackageInstallDepends
#	
#	Returns a list of those ebox packages which will be installed when
#	trying to install a given set of packages
#
# Parameters:
#
# 	packages - an array with the names of the packages being installed
#
# Returns:
#
#	array ref - holding the names of the ebox packages which will be 
#	            installed
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub listPackageInstallDepends
{
	my ($self,$packages) = @_;

        $self->_isModLocked();

	my $cmd = "apt-get -qq -s install " . join(" ", @{$packages}) . " | grep ^Inst | cut -d' ' -f 2 | grep ^ebox";
	my $pkglist = root($cmd);
	my @array = @{$pkglist};
	@array = map { chomp($_); $_ } @array;
	return \@array;
}

# Method: listPackageRemoveDepends
#	
#	Returns a list of those ebox packages which will be removed when
#	trying to remove a given set of packages
#
# Parameters:
#
# 	packages - an array with the names of the packages being removed
#
# Returns:
#
#	array ref - holding the names of the ebox packages which will be removed
#
# Exceptions:
#
#       <EBox::Exceptions::External> - thrown if the module is locked
#       by other process
#
sub listPackageRemoveDepends
{
	my ($self,$packages) = @_;

        $self->_isModLocked();

	my $cmd = "apt-get -qq -s remove " . join(" ", @{$packages}) . " | grep ^Remv | cut -d' ' -f 2 | grep ^ebox";
	my $pkglist = root($cmd);
	my @array = @{$pkglist};
	@array = map { chomp($_); $_ } @array;
	return \@array;
}

# Method: getAutomaticUpdates 
#	
#	Returns if the automatic update mode is enabled
#
# Returns:
#
#	boolean - true if it's enabled, otherwise false
sub getAutomaticUpdates
{
	my $self = shift;
	return $self->get_bool('automatic');
}

# Method: setAutomaticUpdates 
#	
#	Sets the automatic update mode. If it's enabled the system will
#	fetch all the updates silently and automatically.
#
# Parameters:
#
#	auto  - true to enable it, false to disable it
sub setAutomaticUpdates # (auto)
{
	my ($self, $auto) = @_;
	$self->set_bool('automatic', $auto);
}


# Method: menu
#
#       Overrides EBox::Module method.
#
sub menu
{
        my ($self, $root) = @_;
        my $folder = new EBox::Menu::Folder('name' => 'Software',
                                           'text' => __('Software management'));

        $folder->add(new EBox::Menu::Item('url' => 'Software/EBox',
                                          'text' => __('eBox components')));
        $folder->add(new EBox::Menu::Item('url' => 'Software/Updates',
                                          'text' => __('System updates')));
        $folder->add(new EBox::Menu::Item('url' => 'Software/Config',
                                          'text' => __('Automatic updates')));
        $root->add($folder);
}

# Method: lock
#
#      Lock the ebox-software module to work
#
# Parameters:
#
#      by - String the subsystem name which locks the module
#
#      - Named parameters
#
# Exceptions:
#
#      <EBox::Exceptions::MissingArgument> - thrown if any compulsory
#      argument is missing
#
sub lock
{
    my ($self, %params) = @_;

    unless (exists $params{by}) {
        throw EBox::Exceptions::MissingArgument('by');
    }

    open( $self->{lockFile}, '>', LOCK_FILE);
    flock( $self->{lockFile}, LOCK_EX );

    $self->st_set_string(LOCKED_BY_KEY, $params{by});
    $self->st_set_int(LOCKER_PID_KEY, $$);

}

# Method: unlock
#
#      Unlock the ebox-software module
#
# Exceptions:
#
#      <EBox::Exceptions::Internal> - thrown if the module has not
#      previously locked
#
sub unlock
{
    my ($self) = @_;

    unless ( exists( $self->{lockFile} )) {
        throw EBox::Exceptions::Internal('The ebox-module has not '
                                         . 'locked previously');
    }

    flock( $self->{lockFile}, LOCK_UN );
    close( $self->{lockFile} );
    undef $self->{lockFile};

    $self->st_unset(LOCKED_BY_KEY);
    $self->st_unset(LOCKER_PID_KEY);

}


# Group: Private methods

sub _getInfoEBoxPkgs {
	return _getSoftToolResult("i");
}

sub _getUpgradablePkgs {
	return _getSoftToolResult("u");
}

sub _getSoftToolResult {
	my ($command) = @_;
	open(my $PKGS, "/usr/bin/esofttool -$command |")
          or throw EBox::Exceptions::Internal("Cannot open esofttool with command $command");
	my $data = join("",<$PKGS>);
	close($PKGS);
	return eval($data);
}

# Check if the module is locked or not
sub _isModLocked
{
    my ($self) = @_;

    my $lockedBy = $self->st_get_string(LOCKED_BY_KEY);

    if ( $lockedBy ) {
        unless ( $$ == $self->st_get_int(LOCKER_PID_KEY)) {
            throw EBox::Exceptions::External(__x('Software management is currently '
                                                 . ' locked by {locker}. Please, try'
                                                 . ' again later',
                                                 locker => $lockedBy));
        }
    }

}


1;
