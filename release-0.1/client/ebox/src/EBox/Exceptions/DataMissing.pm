package EBox::Exceptions::DataMissing;

use base 'EBox::Exceptions::External';

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my %opts = @_;

	my $data = delete @opts{data};
	my $error = __x("{data} is empty.", data => $data);

	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;

	$self = $class->SUPER::new($error, @_);
	bless ($self, $class);
	return $self;
}
1;
