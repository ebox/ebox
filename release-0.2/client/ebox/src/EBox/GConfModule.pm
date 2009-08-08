# Copyright (C) 2004  Warp Netwoks S.L.
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

package EBox::GConfModule;

use strict;
use warnings;

use base 'EBox::Module';

use Gnome2::GConf;
use EBox::Config;
use EBox::Global;
use EBox::Exceptions::Internal;
use File::Basename;

## options:
##		name [required]
sub _create {
	my $class = shift;
	my %opts = @_;
	my $self = $class->SUPER::_create(@_);
	$self->{gconf} = Gnome2::GConf::Client->get_default;
	defined($self->{gconf}) or
		throw EBox::Exceptions::Internal("Error getting GConf client");
	bless($self, $class);
	$self->gconf->add_dir("/ebox/". $self->name, 'preload-none');
	return $self;
}

sub revokeConfig($) {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');

	$global->modIsChanged($self->name) or return;
	$global->modRestarted($self->name);

	my $file = EBox::Config::conf . "/" . $self->name . ".bak";

	-f $file or return;
	$self->_delete_dir($self->_key(""));
	`/usr/bin/gconftool --load=$file` and
		throw EBox::Exceptions::Internal("Error while restoring " .
						 "configuration from $file");
}

sub _regenConfig {
}

sub restartService($) {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	my $log = EBox::Global->logger;
	$log->debug("Restarting service for module: " . $self->name);
	$self->_regenConfig;
	$global->modRestarted($self->name);
}

sub _backup($) {
	my $self = shift;
	my $global = EBox::Global->modInstance('global');
	$global->modIsChanged($self->name) and return;

	my $key = $self->_key("");
	my $file = EBox::Config::conf . "/" . $self->name . ".bak";
	`/usr/bin/gconftool --dump $key > $file` and
		throw EBox::Exceptions::Internal("Error while backing up " .
						 "configuration on $file");
}

sub gconf($) {
	my $self = shift;
	return $self->{gconf};
}

sub _key($) {
	my ($self, $key) = @_;

	if ($key =~ /^\//) {
		$key =~ s/\/+$//;
		unless ($key =~ /^\/ebox/) {
			throw EBox::Exceptions::Internal("Trying to use a ".
				"gconf key that belongs to a different ".
				"application $key");
		}
		if ($key =~ /^\/ebox$/) {
			throw EBox::Exceptions::Internal("Trying to use a ".
				"gconf key above the module's directory: $key");
		}
		my $name = $self->name;
		unless ($key =~ /^\/ebox\/$name/) {
			throw EBox::Exceptions::Internal("Trying to use a ".
				"gconf key that belongs to a different ".
				"module: $key");
		}
		return $key;
	}

	my $ret = "/ebox/" . $self->name;
	if (defined($key) && $key ne '') {
		$ret .= "/$key";
	}
	return $ret;
}

sub dir_exists($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->dir_exists($key);
}

sub all_dirs_base($$) {
	my ($self, $key) = @_;
	my @array = $self->all_dirs($key);
	my @names = ();
	foreach (@array) {
		push(@names, basename($_));
	}
	return @names;
}

sub all_entries_base($$) {
	my ($self, $key) = @_;
	my @array = $self->all_entries($key);
	my @names = ();
	foreach (@array) {
		push(@names, basename($_));
	}
	return @names;
}

sub all_dirs($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->all_dirs($key);
}

sub all_entries($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->all_entries($key);
}

sub get_bool($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->get_bool($key);
}

sub set_bool($$$) {
	my ($self, $key, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	my $global = EBox::Global->modInstance('global');
	$global->modChange($self->name);
	$self->gconf->set_bool($key, $val);
	$self->gconf->suggest_sync;
}

sub get_int($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->get_int($key);
}

sub set_int($$$) {
	my ($self, $key, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	my $global = EBox::Global->modInstance('global');
	$global->modChange($self->name);
	$self->gconf->set_int($key, $val);
	$self->gconf->suggest_sync;
}

sub get_string($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->get_string($key);
}

sub set_string($$$) {
	my ($self, $key, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	my $global = EBox::Global->modInstance('global');
	$global->modChange($self->name);
	$self->gconf->set_string($key, $val);
	$self->gconf->suggest_sync;
}

sub get_list($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	#FIXME Guillermo check this out  to see if you agree
	#      get_list returns a empty array reference
	#      if empty instead of return undef
	my $list = $self->gconf->get_list($key);
	if ($list){
		return $list;
	} else {
		return [];
	}
}

sub get($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->gconf->get($key);
}

sub unset($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->_backup;
	my $global = EBox::Global->modInstance('global');
	$global->modChange($self->name);
	$self->gconf->unset($key);
	$self->gconf->suggest_sync;
}

sub set_list($$$$) {
	my ($self, $key, $type, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	my $global = EBox::Global->modInstance('global');
	$global->modChange($self->name);
	$self->gconf->set_list($key, $type, $val);
	$self->gconf->suggest_sync;
}

sub hash_from_dir($$) {
	my ($self, $dir) = @_;
	my $hash = {};
	my @keys = $self->all_entries_base($dir);
	foreach (@keys) {
		my $val = $self->get("$dir/$_");
		$hash->{$_} = $val->{value};
	}
	return $hash;
}

sub array_from_dir($$) {
	my ($self, $dir) = @_;
	my @array = ();
	my @subs = $self->all_dirs_base($dir);
	foreach (@subs) {
		push(@array, $self->hash_from_dir("$dir/$_"));
	}
	return \@array;
}

sub delete_dir($$) {
	my ($self, $dir) = @_;
	$self->_backup;
	my $global = EBox::Global->modInstance('global');
	$global->modChange($self->name);
	$dir = $self->_key($dir);
	$self->_delete_dir($dir);
}

sub _delete_dir($$) {
	my ($self, $dir) = @_;
	my @keys = $self->gconf->all_entries($dir);
	foreach (@keys) {
		$self->gconf->unset($_);
	}
	@keys = $self->gconf->all_dirs($dir);
	foreach (@keys) {
		$self->_delete_dir($_);
	}
	$self->gconf->unset($dir);
	$self->gconf->suggest_sync;
}

1;
