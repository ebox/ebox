package EBox::Summary::Item;

use strict;
use warnings;

use EBox::Exceptions::Unknown;

sub new {
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

sub add($$) {
	my $self = shift;
	my $item = shift;
	$item->isa('EBox::Summary::Item') or
		throw EBox::Exceptions::Unknown(
		"Tried to add a non-item to an EBox::Summary::Item composite");

	push(@{$self->items}, $item);
}

sub items($) {
	my $self = shift;
	unless (defined($self->{items})) {
		my @array = ();
		$self->{items} = \@array;
	}
	return $self->{items};
}

sub _htmlitems($) {
	my $self = shift;
	foreach (@{$self->items}) {
		$_->html;
	}
}

sub html($) {
	my $self = shift;
	$self->_htmlitems;
}

1;
