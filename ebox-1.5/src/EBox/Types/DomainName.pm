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

# Class: EBox::Types::DomainName
#
#      A specialised text type to represent an domain name
#
package EBox::Types::DomainName;

use strict;
use warnings;

use base 'EBox::Types::Text';

# eBox uses
use EBox::Validate;
use EBox::Gettext;

# Group: Public methods

# Constructor: new
#
#      The constructor for the <EBox::Types::MACAddr>
#
# Returns:
#
#      the recently created <EBox::Types::MACAddr> object
#
sub new
{
        my $class = shift;
        my $self = $class->SUPER::new(@_);
        $self->{'type'} = 'domainname';
        bless($self, $class);
        return $self;
}

# Method: isEqualTo
#
# Overrides:
#
#      <EBox::Types::Basic::isEqualTo>
#
sub isEqualTo
{
    my ($self, $compareType) = @_;

    return ($self->cmp($compareType) == 0);
}

# Method: cmp
#
# Overrides:
#
#      <EBox::Types::Text::cmp>
#
sub cmp
{
    my ($self, $compareType) = @_;

    unless ( (ref $self) eq (ref $compareType) ) {
        return undef;
    }

    return uc($self->value()) cmp uc($compareType->value());

}

# Group: Protected methods

# Method: _paramIsValid
#
#     Check if the params has a correct domain name
#
# Overrides:
#
#     <EBox::Types::Text::_paramIsValid>
#
# Parameters:
#
#     params - the HTTP parameters with contained the type
#
# Returns:
#
#     true - if the parameter is a correct domainName
#
# Exceptions:
#
#     <EBox::Exceptions::InvalidData> - throw if it's not a correct
#                                       host IP address
#
sub _paramIsValid
{
    my ($self, $params) = @_;

    my $value = $params->{$self->fieldName()};

    if (defined ( $value )) {
        EBox::Validate::checkDomainName($value, $self->printableName());

        my $seemsIp = EBox::Validate::checkIP($value);
        if ($seemsIp) {
            throw EBox::Exceptions::InvalidData
                ('data' => $self->printableName(),
                 'value' => $value,
                 'advice' => __('IP addresses are not allowed'),
                );
        }
    }

    return 1;

}

1;
