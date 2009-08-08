# Copyright (C) 2007 Warp Networks S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package EBox::Types::Int;

use strict;
use warnings;

use base 'EBox::Types::Basic';

# eBox uses
use EBox::Exceptions::External;
use EBox::Gettext;

# Group: Public methods

sub new
{
        my $class = shift;
        my %opts = @_;

        unless (exists $opts{'HTMLSetter'}) {
            $opts{'HTMLSetter'} ='/ajax/setter/textSetter.mas';
        }
        unless (exists $opts{'HTMLViewer'}) {
            $opts{'HTMLViewer'} ='/ajax/viewer/textViewer.mas';
        }
        $opts{'type'} = 'int';
	
        my $self = $class->SUPER::new(%opts);

        bless($self, $class);
        return $self;
}


sub size
{
	my ($self) = @_;

	return $self->{'size'};
}


# Group: Protected methods

# Method: _storeInGConf
#
# Overrides:
#
#       <EBox::Types::Abstract::_storeInGConf>
#
sub _storeInGConf
{
	my ($self, $gconfmod, $key) = @_;

	my $fieldKey ="$key/" . $self->fieldName();

	if (defined($self->memValue()) and $self->memValue() ne '') {
		$gconfmod->set_int($fieldKey, $self->memValue());
	} else {
		$gconfmod->unset($fieldKey);
	}
}

# Method: _paramIsValid
#
# Overrides:
#
#       <EBox::Types::Abstract::_paramIsValid>
#
sub _paramIsValid
{
	my ($self, $params) = @_;

	my $value = $params->{$self->fieldName()};

	unless ($value =~ /^[0-9]+$/) {
            throw EBox::Exceptions::InvalidData( data   => $self->printableName(),
                                                 value  => $value,
                                                 advice => __('Write down a positive number'));
	}

	return 1;

}

# Method: _paramIsSet
#
# Overrides:
#
#       <EBox::Types::Abstract::_paramIsSet>
#
sub _paramIsSet
  {

      my ($self, $params) = @_;

      # Check if the parameter exist
      my $param =  $params->{$self->fieldName()};

      return defined ( $param ) and ( $param ne '');

  }

1;
