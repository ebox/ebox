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

# Class:
#
#   EBox::Squid::Model::ConfigureLogDataTable
#
#   This class is used as a model to describe a table which will be
#   used to select the logs domains the user wants to enable/disable.
#
#   It subclasses <EBox::Model::DataTable>
#
#  
# 

package EBox::Mail::Model::RetrievalServices;
use base 'EBox::Model::DataForm';

use strict;
use warnings;

# eBox classes
use EBox::Global;
use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Types::Boolean;
use EBox::Types::Select;



# eBox exceptions used 
use EBox::Exceptions::External;


# XXX TODO: disable ssl options when no service is enabled
sub new 
{
    my $class = shift @_ ;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}


# Method:  _table
#
# This method overrides <EBox::Model::DataTable::_table> to return
# a table model description.
#
# This table is composed of two fields:
#
#   domain (<EBox::Types::Text>)    
#   enabled (EBox::Types::Boolean>)
# 
# The only avaiable action is edit and only makes sense for 'enabled'.
# 
sub _table
{
    my @tableDesc = 
        ( 
         new EBox::Types::Boolean(
                                  fieldName => 'pop3',
                                  printableName => 'POP3 service enabled',
                                  editable => 1,
                                 ),
         new EBox::Types::Boolean(
                                  fieldName => 'imap',
                                  printableName => 'IMAP service enabled',
                                  editable => 1,
                                 ),
         new EBox::Types::Select(
                                 fieldName => 'ssl',
                                 printableName =>  __('SSL Support'),
                                 editable => 1,
                                 populate => \&_sslSupportOptions,
                                 defaultValue => 'no',
                                ),
        );

      my $dataForm = {
                      tableName          => __PACKAGE__->nameFromClass(),
                      printableTableName => __('Mail retrieval services'),
                      modelDomain        => 'Mail',
                      defaultActions     => [ 'editField', 'changeView' ],
                      tableDescription   => \@tableDesc,

                     };



    return $dataForm;
}




sub _sslSupportOptions
{
    my @options = (
                   { value =>'no' , printableValue =>  __('No') },
                   { value =>'optional' , printableValue =>  __('Optional') },
                   { value =>'required' , printableValue =>  __('Required') },
                   
                  );

    return \@options;
}


1;

