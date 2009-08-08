package EBox::Exceptions::Internal;

use base 'EBox::Exceptions::Base';
use Log::Log4perl;

sub new {
	my $class = shift;

	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;

	$self = $class->SUPER::new(@_);
	bless ($self, $class);

	$Log::Log4perl::caller_depth++;
	$self->log;
	$Log::Log4perl::caller_depth--;

	return $self;
}
1;
