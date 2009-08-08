package EBox::Order;

use strict;
use warnings;

## options:
##		array reference
#		order key name
#
# order numbers must be unique and greater than 1, the do not need to be
# consecutive
sub new($$$) {
	my $class = shift;
	my $self = {};
	$self->{doc} = shift;
	$self->{key} = shift;
	bless($self, $class);
	return $self;
}

sub doc {
	my $self = shift;
	return $self->{doc};
}

sub key {
	my $self = shift;
	return $self->{key};
}

sub highest($) {
	my $self = shift;
	my $high = 0;
	foreach (@{$self->doc}) {
		my $aux = $_->{$self->key};
		if (($aux > $high)) {
			$high = $aux;
		}
	}
	return $high;
}

sub lowest($) {
	my $self = shift;
	my $low = 0;
	foreach (@{$self->doc}) {
		my $aux = $_->{$self->key};
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
	foreach (@{$self->doc}) {
		my $aux = $_->{$self->key};
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
	foreach (@{$self->doc}) {
		my $aux = $_->{$self->key};
		if (($aux < $n) && ($aux > $prev)) {
			$prev = $aux;
		}
	}
	return $prev;
}

sub get($$) {
	my ($self, $n) = @_;
	foreach (@{$self->doc}) {
		if ($_->{$self->key} eq $n) {
			return $_;
		}
	}
	return undef;
}

sub swap($$$) {
	my ($self, $n, $m) = @_;
	foreach (@{$self->doc}) {
		my $aux = $_->{$self->key};
		if ($aux eq $n) {
			$_->{$self->key} = $m;
		} elsif ($aux eq $m) {
			$_->{$self->key} = $n;
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
	return \@array;
}

1;
