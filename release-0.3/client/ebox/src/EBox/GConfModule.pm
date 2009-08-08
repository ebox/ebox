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
use EBox::Gettext;
use EBox::GConfState;
use EBox::GConfConfig;
use File::Basename;

## options:
##		name [required]
sub _create {
	my $class = shift;
	my %opts = @_;
	my $ro = delete $opts{ro};
	my $self = $class->SUPER::_create(@_);
	my $ebox = "ebox";
	if ($self->name ne "global" && $ro) {
		$self->{ro} = 1;
		$ebox = "ebox-ro";
	}
	bless($self, $class);
	$self->{gconf} = Gnome2::GConf::Client->get_default;
	defined($self->{gconf}) or
		throw EBox::Exceptions::Internal("Error getting GConf client");
	$self->gconf->add_dir("/$ebox/modules/". $self->name, 'preload-none');
	$self->gconf->add_dir("/$ebox/state/". $self->name, 'preload-none');
	$self->{state} = new EBox::GConfState($self, $self->{ro});
	$self->{config} = new EBox::GConfConfig($self, $self->{ro});
	$self->{helper} = $self->{config};
	if ($self->name ne "global" && $ro) {
		my $global = EBox::Global->getInstance();
		unless ($global->modIsChanged($self->name)) {
			$self->_dump_to_file;
		}
		$self->_load_from_file;
	}
	return $self;
}

sub _helper($) {
	my $self = shift;
	return $self->{helper};
}

sub _config($) {
	my $self = shift;
	$self->{helper} = $self->{config};
}

sub _state($) {
	my $self = shift;
	$self->{helper} = $self->{state};
}

sub _load_from_file($) {
	my $self = shift;

	my $file = EBox::Config::conf . "/" . $self->name . ".bak";
	-f $file or throw EBox::Exceptions::Internal("Backup file missing: ".
							"$file.");
	my $key = $self->_key("");
	$self->_delete_dir_internal($key);
	`/usr/bin/gconftool --load=$file $key` and
		throw EBox::Exceptions::Internal("Error while restoring " .
						 "configuration from $file");
}

sub _dump_to_file($) {
	my $self = shift;
	my $key = "/ebox/modules/" . $self->name;
	my $file = EBox::Config::conf . "/" . $self->name . ".bak";
	`/usr/bin/gconftool --dump $key > $file` and
		throw EBox::Exceptions::Internal("Error while backing up " .
						 "configuration on $file");
}

sub isReadOnly($) {
	my $self = shift;
	return $self->{ro};
}

sub revokeConfig($) {
	my $self = shift;
	my $global = EBox::Global->getInstance();

	$global->modIsChanged($self->name) or return;
	$global->modRestarted($self->name);

	my $ro = $self->{ro};
	$self->{ro} = undef;
	$self->_load_from_file();
	$self->{ro} = $ro;
}

sub _backup($) {
	my $self = shift;
	$self->_helper->backup();
}

sub gconf($) {
	my $self = shift;
	return $self->{gconf};
}

sub _key($) {
	my ($self, $key) = @_;
	return $self->_helper->key($key);
}

#############

sub _gconf_wrapper($$;@){
	my $self = shift;
	my $method = shift;
	my @parms  = @_;
	my $scalar;
	my @array;

	my $code = $self->gconf->can($method);
	unless ($code){
		throw EBox::Exceptions::Internal("method $method  doesnt exists"
						 . " in EBox::GConfModule\n");
	}

	my $ret = wantarray;
	eval { 
		if ($ret){
			@array = &$code($self->gconf, @parms);
		} else {
			$scalar = &$code($self->gconf, @parms);
		}	
	};
	if ($@) {
		throw EBox::Exceptions::Internal("gconf error using function "
						 . "$method and params @parms"
						 . "\n $@");
	}

	return wantarray ? @array : $scalar;	
}

sub _dir_exists($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->_gconf_wrapper("dir_exists", $key);
}

sub dir_exists($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_dir_exists($key);
}

sub st_dir_exists($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_dir_exists($key);
}

#############

sub _all_dirs_base($$) {
	my ($self, $key) = @_;
	my @array = $self->_all_dirs($key);
	my @names = ();
	foreach (@array) {
		push(@names, basename($_));
	}
	return \@names;
}

sub all_dirs_base($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_all_dirs_base($key);
}

sub st_all_dirs_base($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_all_dirs_base($key);
}

#############

sub _all_entries_base($$) {
	my ($self, $key) = @_;
	my @array = $self->_all_entries($key);
	my @names = ();
	foreach (@array) {
		push(@names, basename($_));
	}
	return \@names;
}

sub all_entries_base($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_all_entries_base($key);
}

sub st_all_entries_base($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_all_entries_base($key);
}

#############

sub _all_dirs($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->_gconf_wrapper("all_dirs", $key);
}

sub all_dirs($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_all_dirs($key);
}

sub st_all_dirs($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_all_dirs($key);
}

#############

sub _all_entries($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	return $self->_gconf_wrapper("all_entries", $key);
}

sub all_entries($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_all_entries($key);
}

sub st_all_entries($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_all_entries($key);
}

#############

sub _get_bool($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->gconf->suggest_sync;
	return $self->_gconf_wrapper("get_bool", $key);
}

sub get_bool($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_get_bool($key);
}

sub st_get_bool($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_get_bool($key);
}

#############

sub _set_bool($$$) {
	my ($self, $key, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	$self->_gconf_wrapper("set_bool", $key, $val);
	$self->gconf->suggest_sync;
}

sub set_bool($$$) {
	my ($self, $key, $val) = @_;
	$self->_config;
	$self->_set_bool($key, $val);
}

sub st_set_bool($$$) {
	my ($self, $key, $val) = @_;
	$self->_state;
	$self->_set_bool($key, $val);
}

#############

sub _get_int($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->gconf->suggest_sync;
	return $self->_gconf_wrapper("get_int", $key);
}

sub get_int($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_get_int($key);
}

sub st_get_int($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_get_int($key);
}

#############

sub _set_int($$$) {
	my ($self, $key, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	$self->_gconf_wrapper("set_int", $key, $val);
	$self->gconf->suggest_sync;
}

sub set_int($$$) {
	my ($self, $key, $val) = @_;
	$self->_config;
	$self->_set_int($key, $val);
}

sub st_set_int($$$) {
	my ($self, $key, $val) = @_;
	$self->_state;
	$self->_set_int($key, $val);
}

#############

sub _get_string($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->gconf->suggest_sync;
	return $self->_gconf_wrapper("get_string", $key);
}

sub get_string($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_get_string($key);
}

sub st_get_string($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_get_string($key);
}

#############

sub _set_string($$$) {
	my ($self, $key, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	$self->_gconf_wrapper("set_string", $key, $val);
	$self->gconf->suggest_sync;
}

sub set_string($$$) {
	my ($self, $key, $val) = @_;
	$self->_config;
	$self->_set_string($key, $val);
}

sub st_set_string($$$) {
	my ($self, $key, $val) = @_;
	$self->_state;
	$self->_set_string($key, $val);
}

#############

sub _get_list($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->gconf->suggest_sync;
	my $list = $self->_gconf_wrapper("get_list", $key);
	if ($list){
		return $list;
	} else {
		return [];
	}
}

sub get_list($$) {
	my ($self, $key) = @_;
	$self->_config;
	return $self->_get_list($key);
}

sub st_get_list($$) {
	my ($self, $key) = @_;
	$self->_state;
	return $self->_get_list($key);
}

#############

sub _get($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->gconf->suggest_sync;
	return $self->_gconf_wrapper("get", $key);
}

#############

sub _unset($$) {
	my ($self, $key) = @_;
	$key = $self->_key($key);
	$self->_backup;
	$self->_gconf_wrapper("unset", $key);
	$self->gconf->suggest_sync;
}

sub unset($$) {
	my ($self, $key) = @_;
	$self->_config;
	$self->_unset($key);
}

sub st_unset($$) {
	my ($self, $key) = @_;
	$self->_state;
	$self->_unset($key);
}

#############

sub _set_list($$$$) {
	my ($self, $key, $type, $val) = @_;
	$key = $self->_key($key);
	$self->_backup;
	$self->_gconf_wrapper("set_list", $key, $type, $val);
	$self->gconf->suggest_sync;
}

sub set_list($$$$) {
	my ($self, $key, $type, $val) = @_;
	$self->_config;
	$self->_set_list($key, $type, $val);
}

sub st_set_list($$$$) {
	my ($self, $key, $type, $val) = @_;
	$self->_state;
	$self->_set_list($key, $type, $val);
}

#############

sub _hash_from_dir($$) {
	my ($self, $dir) = @_;
	my $hash = {};
	my @keys = @{$self->_all_entries_base($dir)};
	foreach (@keys) {
		my $val = $self->_get("$dir/$_");
		$hash->{$_} = $val->{value};
	}
	return $hash;
}

sub hash_from_dir($$) {
	my ($self, $dir) = @_;
	$self->_config;
	return $self->_hash_from_dir($dir);
}

sub st_hash_from_dir($$) {
	my ($self, $dir) = @_;
	$self->_state;
	return $self->_hash_from_dir($dir);
}

#############

sub _array_from_dir($$) {
	my ($self, $dir) = @_;
	my @array = ();
	my @subs = @{$self->_all_dirs_base($dir)};
	foreach (@subs) {
		push(@array, $self->_hash_from_dir("$dir/$_"));
	}
	return \@array;
}

sub array_from_dir($$) {
	my ($self, $dir) = @_;
	$self->_config;
	return $self->_array_from_dir($dir);
}

sub st_array_from_dir($$) {
	my ($self, $dir) = @_;
	$self->_state;
	return $self->_array_from_dir($dir);
}

#############

sub _delete_dir($$) {
	my ($self, $dir) = @_;
	$self->_backup;
	$dir = $self->_key($dir);
	$self->_delete_dir_internal($dir);
}

sub delete_dir($$) {
	my ($self, $dir) = @_;
	$self->_config;
	$self->_delete_dir($dir);
}

sub st_delete_dir($$) {
	my ($self, $dir) = @_;
	$self->_state;
	$self->_delete_dir($dir);
}

#############

sub _delete_dir_internal($$) {
	my ($self, $dir) = @_;
	my @keys = $self->_gconf_wrapper("all_entries", $dir);
	foreach (@keys) {
		$self->_gconf_wrapper("unset", $_);
	}
	@keys = $self->_gconf_wrapper("all_dirs", $dir);
	foreach (@keys) {
		$self->_delete_dir_internal($_);
	}
	$self->_gconf_wrapper("unset", $dir);
	$self->gconf->suggest_sync;
}

1;
