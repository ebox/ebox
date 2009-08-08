package EBox::Exceptions::External;

use base 'EBox::Exceptions::Base';

sub new {
	my $class = shift;

	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;

	$self = $class->SUPER::new(@_);
	bless ($self, $class);
	return $self;
}
1;
