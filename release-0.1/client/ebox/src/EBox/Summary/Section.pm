package EBox::Summary::Section;

use strict;
use warnings;

use base 'EBox::Summary::Item';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new();
	$self->{title} = shift;
	bless($self, $class);
	return $self;
}

sub html($) {
	my $self = shift;
	print '<h3>';
	print $self->{title};
	print '</h3>';
	print '<table>';
	print '<tbody>';
	$self->_htmlitems;
	print '</tbody>';
	print '</table>';
}

1;
