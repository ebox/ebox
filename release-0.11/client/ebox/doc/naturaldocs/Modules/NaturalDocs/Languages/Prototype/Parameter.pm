###############################################################################
#
#   Class: NaturalDocs::Languages::Prototype::Parameter
#
###############################################################################
#
#   A data class for storing parsed prototype parameters.
#
###############################################################################

use strict;
use integer;

package NaturalDocs::Languages::Prototype::Parameter;

use NaturalDocs::DefineMembers 'TYPE', 'Type()', 'SetType()',
                                                 'TYPE_PREFIX', 'TypePrefix()', 'SetTypePrefix()',
                                                 'NAME', 'Name()', 'SetName()',
                                                 'NAME_PREFIX', 'NamePrefix()', 'SetNamePrefix()',
                                                 'DEFAULT_VALUE', 'DefaultValue()', 'SetDefaultValue()';
# Dependency: New() depends on the order of these constants and that they don't inherit from another class.


#
#   Function: New
#
#   Creates and returns a new prototype object.
#
#   Parameters:
#
#       type - The parameter type, if any.
#       typePrefix - The parameter type prefix which should be aligned separately, if any.
#       name - The parameter name.
#       namePrefix - The parameter name prefix which should be aligned separately, if any.
#       defaultValue - The default value expression, if any.
#
sub New #(type, typePrefix, name, namePrefix, defaultValue)
    {
    my ($package, @params) = @_;

    # Dependency: This depends on the order of the parameters being the same as the order of the constants, and that the
    # constants don't inherit from another class.

    my $object = [ @params ];
    bless $object, $package;

    return $object;
    };


#
#   Functions: Members
#
#   Type - The parameter type, if any.
#   SetType - Replaces the parameter type.
#   TypePrefix - The parameter type prefix, which should be aligned separately, if any.
#   SetTypePrefix - Replaces the parameter type prefix.
#   Name - The parameter name.
#   SetName - Replaces the parameter name.
#   NamePrefix - The parameter name prefix, which should be aligned separately, if any.
#   SetNamePrefix - Replaces the parameter name prefix.
#   DefaultValue - The default value expression, if any.
#   SetDefaultValue - Replaces the default value expression.
#


1;
