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


package EBox::Radius::Model::Auth;

# Class: EBox::Radius::Model::Auth
#
#       Form to set the Auth configuration for the RADIUS server
#

use base 'EBox::Model::DataForm';

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;
use EBox::Types::Select;

# Group: Public methods

# Constructor: new
#
#       Create the new Auth model
#
# Overrides:
#
#       <EBox::Model::DataForm::new>
#
# Returns:
#
#       <EBox::Radius::Model::Auth> - the recently created model
#
sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    bless ( $self, $class );

    return $self;
}


# Method: getByGroup
#
#      Returns true if a group has been selected
#
# Returns:
#
#      boolean
#
sub getByGroup
{
    my ($self) = @_;

    my $row = $self->row();

    return ($row->valueByName('group') ne '1901');
}


# Method: getGroup
#
#      Returns the allowed group
#
# Returns:
#
#      string
#
sub getGroup
{
    my ($self) = @_;

    my $row = $self->row();

    return $row->printableValueByName('group');
}


# Group: Private methods

# Method: _groups
#
#  Returns:
#
sub _groups
{
    my @groups = ( { value => 1901, printableValue => __('All users') });
    my $users = EBox::Global->modInstance('users');
    return \@groups unless ($users->configured());
    my @sortedGroups = sort { $a->{account} cmp $b->{account} } $users->groups();
    for my $group (@sortedGroups) {
        push (@groups, { value => $group->{gid},
                printableValue => $group->{account} });
    }
    return \@groups;
}


# Method: _table
#
# Overrides:
#
#      <EBox::Model::DataTable::_table>
#
sub _table
{

    my @tableHeader =
      (
       new EBox::Types::Select(
           'fieldName'     => 'group',
           'printableName' => __('Group allowed to authenticate'),
           'populate'      => \&_groups,
           'editable'      => 1,
           'noCache'       => 0,
           ),
      );

    my $dataTable =
    {
        tableName          => 'Auth',
        printableTableName => __('General configuration'),
        defaultActions     => [ 'editField', 'changeView' ],
        tableDescription   => \@tableHeader,
        class              => 'dataForm',
        help               => __("RADIUS server configuration"),
        messages           => {
                                  update => __('RADIUS server configuration updated'),
                              },
        modelDomain        => 'Radius',
    };

    return $dataTable;

}

1;
