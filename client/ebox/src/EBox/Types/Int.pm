package EBox::Types::Int;

use strict;
use warnings;

use base 'EBox::Types::Basic';


sub new
{
        my $class = shift;
	my %opts = @_;
	my $self = $class->SUPER::new(@_);


        bless($self, $class);
        return $self;
}

sub paramIsValid
{
	my ($self, $params) = @_;

	my $value = $params->{$self->fieldName()};

	unless (defined($value)) {
		return 0;
	}

	unless ($value =~ /^[0-9]+$/) {
		return 0;
	}

	return 1;

}

sub size
{
	my ($self) = @_;

	return $self->{'size'};
}

sub storeInGconf
{
	my ($self, $gconfmod, $key) = @_;

	my $fieldKey ="$key/" . $self->fieldName();

	if (defined($self->memValue()) and $self->memValue() ne '') {
		$gconfmod->set_int($fieldKey, $self->memValue());
	} else {
		$gconfmod->unset($fieldKey);
	}
}

sub HTMLSetter
{
	
	return 'textSetter';

}

sub HTMLViewer
{
        return 'textViewer';
}

1;
