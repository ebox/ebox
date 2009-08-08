package EBox::Exceptions::Base;

use base 'Error';
use Log::Log4perl;

sub new {
	my $class = shift;
	my $text = shift;

	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;

	$self = $class->SUPER::new(-text => $text, @_);
	bless ($self, $class);
	return $self;
}

sub toStderr {
	#TODO
	$self = shift;
	print STDERR "[EBox::Exceptions] ". $self->text ."\n";
}

sub _logfunc($$$) {
	my ($self, $logger, $msg) = @_;
	$logger->debug($msg);
}

sub log {
	$self = shift;
	my $log = EBox::Global->logger;
	$Log::Log4perl::caller_depth +=3;
	$self->_logfunc($log, $self->text);
	$Log::Log4perl::caller_depth -=3;
}
1;
