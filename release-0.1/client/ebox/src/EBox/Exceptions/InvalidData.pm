package EBox::Exceptions::InvalidData;

use base 'EBox::Exceptions::External';

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my %opts = @_;

	my $data = delete @opts{data};
	my $value = delete @opts{value};
	my $error = __x("Invalid {data} value: {value}.", data => $data,
							 value => $value);

	local $Error::Depth = $Error::Depth + 1;
	local $Error::Debug = 1;

	$self = $class->SUPER::new($error, @_);
	bless ($self, $class);
	return $self;
}
1;
