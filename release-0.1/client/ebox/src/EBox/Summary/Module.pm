package EBox::Summary::Module;

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
	print '<h2>';
	print $self->{title};
	print '</h2>';
	$self->_htmlitems;
}

1;
