package EBox::Summary::Value;

use strict;
use warnings;

use base 'EBox::Summary::Item';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new();
	$self->{key} = shift;
	$self->{value} = shift;
	bless($self, $class);
	return $self;
}

sub html($) {
	my $self = shift;
	print '<tr>';
	print '<td>';
	print $self->{key};
	print '</td>';
	print '<td>';
	print $self->{value};
	print '</td>';
	print '</tr>';
	$self->_htmlitems;
}

1;
