# TODO 
# 	* Optimize class. Use reference to fetch selected type 
#         instead of transverse array.
#
#       * Support automatic unique check
#
package EBox::Types::Union;

use strict;
use warnings;

use base 'EBox::Types::Abstract';

sub new
{
        my $class = shift;
	my %opts = @_;
	my $self = {@_};

        bless($self, $class);
        return $self;
}

sub subtype
{
	my ($self) = @_;
	
	my $selected = $self->selectedType();
	
	foreach my $type (@{$self->{'subtypes'}}) {
		if ($type->fieldName() eq $selected) {
			return $type;
		}
	}

	return "";

}

sub selectedType
{
	my ($self) = @_;

	return $self->{'selectedField'};
}

sub setSelectedType
{
	my ($self, $field) = @_;

	$self->{'selectedField'} = $field;
}

sub subtypes
{
	my ($self) = @_;

	return $self->{'subtypes'};
}

sub unique
{
	my ($self) = @_;

	# So far we do not check if it is unique
	return 0;
}



sub fields
{
	my ($self) = @_;

	my @fields;
	foreach my $type (@{$self->{'subtypes'}}) {
		push (@fields, $type->fields());
	
	}
	
	push (@fields, $self->fieldName() . '_selected');
	
	return @fields;
}


sub printableValue
{
	my ($self) = @_;

	my $selected = $self->selectedType();
	
	foreach my $type (@{$self->{'subtypes'}}) {
		if ($type->fieldName() eq $selected) {
			return $type->printableValue();
		}
	}

	return "";

}

sub paramExist
{
        my ($self, $params) = @_;

	my $selPar = $self->fieldName() . '_selected';
	my $selected = $params->{$selPar};
	
	return 0 unless (defined($selected)); 
	
	foreach my $type (@{$self->{'subtypes'}}) {
		next unless ($type->fieldName() eq $selected);
		return $type->paramExist($params);
	}

	return 0;
}

sub paramIsValid
{

	return 1;
}

sub storeInGconf
{
        my ($self, $gconfmod, $key) = @_;
	
	my $selected = $self->selectedType();
	
	foreach my $type (@{$self->{'subtypes'}}) {
		if ($type->fieldName() eq $selected) {
			$type->storeInGconf($gconfmod, $key);
			
			my $selKey = "$key/" . $self->fieldName() 
				     . '_selected';
				     
			$gconfmod->set_string($selKey, $self->selectedType());
		}
	}
}

sub restoreFromGconf
{

}

sub setMemValue
{
	my ($self, $params) = @_;

	unless ($self->paramExist($params)) {
		throw EBox::Exceptions::MissingArgument(
						$self->printableName());
	}
	
	my $selPar = $self->fieldName() . '_selected';
	my $selected = $params->{$selPar};
	
	foreach my $type (@{$self->{'subtypes'}}) {
		if ($type->fieldName() eq $selected) {
			$type->setMemValue($params);
			$self->setSelectedType($selected);
		}
	}
	
}

sub memValue
{

}

sub compareToHash
{

}

sub restoreFromHash
{
	my ($self, $hash) = @_;

	my $selPar = $self->fieldName() . '_selected';
	
	my $selected = $hash->{$selPar};
	
	foreach my $type (@{$self->{'subtypes'}}) {
		next unless ($type->fieldName() eq $selected);
		
		$type->restoreFromHash($hash);
		$self->setSelectedType($selected);
	}
	
}

sub isEqualTo
{
	my ($self, $newObject) = @_;

	return ($self->printableValue() eq $newObject->printableValue());
}

sub HTMLSetter
{
	return 'unionSetter';
}

sub HTMLViewer
{
	my ($self) = @_;
	
	my $selected = $self->selectedType();
	
	foreach my $type (@{$self->{'subtypes'}}) {
		next unless ($type->fieldName() eq $selected);
		return $type->HTMLViewer();
	}
}

1;
