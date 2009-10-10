# Copyright (C) 2009 eBox Technologies S.L.
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


package EBox::EBackup::Model::RemoteFileList;

# Class: EBox::EBackup::Model::RemoteFileList
#
#
#

use base 'EBox::Model::DataTable';

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;
use EBox::Types::Select;
use EBox::Types::Text;

# Group: Public methods

# Constructor: new
#
#       Create the new Hosts model
#
# Overrides:
#
#       <EBox::Model::DataForm::new>
#
# Returns:
#
#       <EBox::EBackup::Model::Hosts> - the recently created model
#
sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    bless ( $self, $class );

    return $self;
}

# Method: ids
#
# Overrides:
#
#      <EBox::Model::DataTable::ids>
#
sub ids
{
    my ($self) = @_;

    my @status = @{$self->{gconfmodule}->remoteListFiles()};
    return [] unless (@status);
    return [0 .. (scalar(@status) -1)];
}

# Method: customFilterIds
#
# Overrides:
#
#      <EBox::Model::DataTable::customFilterIds>
#
sub customFilterIds
{
    my ($self, $filter) = @_;

    unless (defined($filter)) {
        return $self->ids();
    }

    my @status = @{$self->{gconfmodule}->remoteListFiles()};
    return [] unless (@status);
    my @filtered;
    for my $id (0 .. (scalar(@status) -1)) {
        push (@filtered, $id) if ($status[$id] =~ /$filter/);
    }

    return \@filtered;
}

# Method: row
#
# Overrides:
#
#      <EBox::Model::DataTable::row>
#
sub row
{
    my ($self, $id) = @_;

    my @status = @{$self->{gconfmodule}->remoteListFiles()};

    my $row = $self->_setValueRow(file => $status[$id]);
    $row->setId($id);
    return $row;
}

# Group: Protected methods

# Method: _table
#
# Overrides:
#
#      <EBox::Model::DataTable::_table>
#
sub _table
{

    my @tableHeader = (
        new EBox::Types::Text(
            fieldName     => 'file',
            printableName => __('File'),
        ),
        new EBox::Types::Select(
            fieldName     => 'date',
            printableName => __('Backup Date'),
            populate      => \&_backupVersion,
            editable      => 1,
            disableCache  => 1,
       )

    );

    my $dataTable =
    {
        tableName          => 'RemoteFileList',
        printableTableName => __('Remote File List'),
        printableRowName   => __('file restore operation'),
        defaultActions     => ['editField', 'changeView' ],
        tableDescription   => \@tableHeader,
        class              => 'dataTable',
        modelDomain        => 'EBackup',
        defaultEnabledValue => 1,
        customFilter       => 1,
    };

    return $dataTable;

}

sub _backupVersion
{
    my $ebackup = EBox::Global->modInstance('ebackup');
    my @status = @{$ebackup->remoteStatus()};
    return [] unless (@status);
    my @versions;
    for my $id (@status) {
        push (@versions, {
                value => $id->{'date'},
                printableValue => $id->{'date'}
        });
    }
    return \@versions;
}

# Method: headTitle
#
# Overrides:
#
#       <EBox::Model::Composite::headTitle>
#
sub headTitle
{
    return undef;
}

1;
