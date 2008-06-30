# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
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

# Class: EBox::Firewall::Model::BaseRuleTable
#
# This class is used as a base for firewall models, as they are pretty
# similar. All of them use objects, services, and decisions.
#
# The only difference is which kind of table the define. Tables used
# to filter traffic from and to eBox do not need a destination field.
#
# You must use _fieldDescription to decide if you want to have
# a destination field.
# 
# 	
package EBox::Firewall::Model::BaseRuleTable;

use EBox::Global;
use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Exceptions::External;

use EBox::Types::Text;
use EBox::Types::Union::Text;
use EBox::Types::Boolean;
use EBox::Types::Select;
use EBox::Types::InverseMatchSelect;
use EBox::Types::IPAddr;
use EBox::Types::InverseMatchUnion;
use EBox::Sudo;


use strict;
use warnings;


use base 'EBox::Model::DataTable';


sub new 
{
    my $class = shift;
    my %parms = @_;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}

sub decision 
{
    my @options = ({ 'value' => 'accept', 
             'printableValue' => __('ACCEPT') }, 
               { 'value' => 'deny',
             'printableValue' => __('DENY') });
    return \@options;
}

sub serviceModel
{
   return  EBox::Global->modInstance('services')->{'serviceModel'};  
}

sub objectModel
{
    return EBox::Global->modInstance('objects')->{'objectModel'};
}

# Method: _fieldDescription
#
#   Return the field description for a firewall rule table. You have to
#   decided if you need destination, source, or both of them.
#
#
# Parameters:
#
#   (NAMED)
#
#   destination - boolean to indicate you need a destination field
#   source - boolean to indicate you need a source field
#   
# Returns:
#
#   Array ref of objects derivated of <EBox::Types::Abstract>	
sub _fieldDescription
{
    my ($self, %params) = @_;
    
    
    
    my @tableHead = 
        ( 
       
        new EBox::Types::Select(
             'fieldName' => 'decision',
             'printableName' => __('Decision'),
             'populate' => \&decision,
             'HTMLViewer' => '/ajax/viewer/fwDecisionViewer.mas',
             'editable' => 1
             ));
             
    if ($params{'source'}) {             
        my $source = new EBox::Types::InverseMatchUnion(
                         'fieldName' => 'source',
                         'printableName' => __('Source'),
                         'subtypes' =>
                            [
                             new EBox::Types::Union::Text(
                                'fieldName' => 'source_any',
                                 'printableName' => __('Any')),
                             new EBox::Types::IPAddr(
                                 'fieldName' => 'source_ipaddr',
                                 'printableName' => __('Source IP'),
                                 'editable' => 1,),
                             new EBox::Types::Select(
                                 'fieldName' => 'source_object',
                                 'printableName' => __('Source object'),
                                 'foreignModel' => \&objectModel,
                                 'foreignField' => 'name',
                                 'editable' => 1),
                             ],
                         'unique' => 1,
                         'editable' => 1
                          );
        push (@tableHead, $source);
    }

    if ($params{'destination'}) {
       my $dest=  new EBox::Types::InverseMatchUnion(
                         'fieldName' => 'destination',
                         'printableName' => __('Destination'),
                         'subtypes' =>
                            [
                            new EBox::Types::Union::Text(
                                 'fieldName' => 'destination_any',
                                 'printableName' => __('Any')),
                             new EBox::Types::IPAddr(
                                 'fieldName' => 'destination_ipaddr',
                                 'printableName' => __('Destination IP'),
                                 'editable' => 1,
                                 'optional' => 1),
                             new EBox::Types::Select(
                                 'fieldName' => 'destination_object',
                                 'printableName' => __('Destination object'),
                                 'foreignModel' => \&objectModel,
                                 'foreignField' => 'name',
                                 'editable' => 1),
                             ],
                         'unique' => 1,
                         'editable' => 1
                          );

        push (@tableHead, $dest);
    }

    push (@tableHead, 
       new EBox::Types::InverseMatchSelect(
             'fieldName' => 'service',
             'printableName' => __('Service'), 
             'foreignModel' => \&serviceModel,
             'foreignField' => 'name',
             'editable' => 1
             ),
       new EBox::Types::Text(
             'fieldName' => 'description',
             'printableName' => __('Description'),
             'size' => '15',
             'editable' => 1,
             'optional' => 1,
             ),
#        new EBox::Types::Boolean(
#                 'fieldName' => 'log',
#                 'printableName' => __('Log'),
#                 'editable' => 1
#                 )

             );
    
    return \@tableHead;
}
1;
