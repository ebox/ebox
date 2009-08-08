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

package EBox::Order;

use strict;
use warnings;

## options:
##		module
#		gconf directory
#
# order numbers must be unique and greater than 1, the do not need to be
# consecutive
sub new($$$) {
	my $class = shift;
	my $self = {};
	$self->{mod} = shift;
	$self->{key} = shift;
	bless($self, $class);
	return $self;
}

sub mod {
	my $self = shift;
	return $self->{mod};
}

sub key {
	my $self = shift;
	return $self->{key};
}

sub highest($) {
	my $self = shift;
	my $high = 0;
	my @keys = $self->mod->all_dirs($self->key);
	foreach (@keys) {
		my $aux = $self->mod->get_int("$_/order");
		if (($aux > $high)) {
			$high = $aux;
		}
	}
	return $high;
}

sub lowest($) {
	my $self = shift;
	my $low = 0;
	my @keys = $self->mod->all_dirs($self->key);
	foreach (@keys) {
		my $aux = $self->mod->get_int("$_/order");
		if (($low < 1) || ($aux < $low)) {
			$low = $aux;
		}
	}
	return $low;
}

sub nextn($$) {
	my ($self, $n) = @_;
	my $next = $self->highest;
	if ($next < 1) {
		return $n;
	}
	my @keys = $self->mod->all_dirs($self->key);
	foreach (@keys) {
		my $aux = $self->mod->get_int("$_/order");
		if (($aux > $n) && ($aux < $next)) {
			$next = $aux;
		}
	}
	return $next;
}

sub prevn($$) {
	my ($self, $n) = @_;
	my $prev = $self->lowest;
	if ($prev < 1) {
		return $n;
	}
	my @keys = $self->mod->all_dirs($self->key);
	foreach (@keys) {
		my $aux = $self->mod->get_int("$_/order");
		if (($aux < $n) && ($aux > $prev)) {
			$prev = $aux;
		}
	}
	return $prev;
}

sub get($$) {
	my ($self, $n) = @_;
	my @keys = $self->mod->all_dirs($self->key);
	foreach (@keys) {
		if ($self->mod->get_int("$_/order") eq $n) {
			return $_;
		}
	}
	return undef;
}

sub swap($$$) {
	my ($self, $n, $m) = @_;
	my @keys = $self->mod->all_dirs($self->key);
	foreach (@keys) {
		my $aux = $self->mod->get_int("$_/order");
		if ($aux eq $n) {
			$self->mod->set_int("$_/order", $m);
		} elsif ($aux eq $m) {
			$self->mod->set_int("$_/order", $n);
		}
	}
}

sub list($) {
	my $self = shift;
	my @array = ();
	my $i = $self->lowest;
	my $high = $self->highest;
	if ($i < 1) {
		return \@array;
	}

	while (1) {
		push(@array, $self->get($i));
		if ($i eq $high) {
			last
		}
		$i = $self->nextn($i);
	}
	return @array;
}

1;
