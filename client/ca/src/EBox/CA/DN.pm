# Copyright (C) 2006 Warp Networks S.L.
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

package EBox::CA::DN;

use Storable qw(dclone);

# Constants
use constant COUNTRY_DEF => "ES";
use constant LOCALITY_DEF => "Nowhere";
use constant STATE_DEF   => "Nation";


# Method: new
#
#       Constructor for DN class.
#       This class stores and manages the Distinguished Name
#       defined in X.500 specification.
#
# Parameters:
#
#       countryName - the country name {2 letter code}
#       stateName   - the state name
#       localityName    - the locality name
#       organizationName - the Organization Name
#       organizationNameUnit -  the Organization Unit Name
#       commonName - the common name
#
# Returns:
#
#       the recently created object
#
sub new {

	my ($class, %args) = @_;
	my $self = {};

	bless($self, $class);

	$self->{countryName} = $args{countryName};
	$self->{countryName} = COUNTRY_DEF unless ( $self->{countryName} );
	$self->{stateName} = $args{stateName};
	$self->{stateName} = STATE_DEF unless ( $self->{stateName} );
	$self->{localityName} = $args{localityName};
	$self->{localityName} = LOCALITY_DEF unless ( $self->{localityName} );
	$self->{organizationName} = $args{organizationName};
	$self->{organizationNameUnit} = $args{organizationNameUnit};
	$self->{commonName} = $args{commonName};

	return $self;
}

# Method: parseDN
#
#       Constructor for DN class.
#       From a /type0=value0/... environment take
#       the distinguish name fields
#
# Parameters:
#
#       parameters - the string containg the parameters
#                    in /type0=value=0/ style
#
# Returns:
#
#       the recently created object with the parameters
#
sub parseDN
  {

  	my ($class, $parameters) = @_;
	my $self = {};

	bless($self, $class);

	return undef unless defined ($parameters);

	chomp($parameters);

	my @fields = split('/', $parameters);

	foreach my $field (@fields) {

	  my ($type, $value) = split('=', $field);

	  $self->{countryName} = $value if ($type eq "C");
	  $self->{stateName} = $value if ($type eq "ST");
	  $self->{localityName} = $value if ($type eq "L");
	  $self->{organizationName} = $value if ($type eq "O");
	  $self->{organizationUnitName} = $value if ($type eq "OU");
	  $self->{commonName} = $value if ($type eq "CN");

	}

	return $self;
      }

# Method: copy
#
#       Clone the DN object
#
# Returns:
#
#       the recently cloned object
#
sub copy {

  my $self = shift;

  my $copy = Storable::dclone($self);
  
  return $copy;

}

# Method: stringOpenSSLStyle
#
#       the string containing the DN with an acceptable format
#       to pass to open ssl
#
#
# Returns:
#
#       a String with the following format: /type0=value0/type1=value1/...
#
sub stringOpenSSLStyle {

  my $self = shift;

  my $outStr = "";

  $outStr .= "/C=" . $self->{countryName}
    if ($self->{countryName});
 
  $outStr .= "/ST=" . $self->{stateName}
    if ($self->{stateName});

  $outStr .= "/L=" . $self->{localityName}
    if ($self->{localityName});

  $outStr .= "/O=" . $self->{organizationName}
    if ($self->{organizationName});

  $outStr .= "/OU=" . $self->{organizationNameUnit}
    if ($self->{organizationNameUnit});
  
  $outStr .= "/CN=" . $self->{commonName}
    if ($self->{commonName});

  $outStr .= "/";

  return $outStr;

}


# Method: dnAttribute
#
#       set and get method for an attribute in a
#       distinguished name
#
# Parameters:
#
#       attributeName - the attribute name (It can be one of the
#       following: countryName, stateName, localityName,
#       OrganizationName, OrganizationNameUnit, commonName
#       value - the new common name (Optional)
#
# Returns:
#
#       a String representing the attribute value to set or get
#       or undef if the attribute does NOT exist
#
sub dnAttribute
  {

    my ($self, $attrName, $value) = @_;

    if ( $self->{$attrName} ) {
      $self->{$attrName} = $value if defined($value);
    }

    return $self->{$attrName};

  }



1;
