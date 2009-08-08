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


# Class: EBox::LogObserver
#
#	Those modules FIXME to process logs generated by their
#	daemon or servide must inherit from this class and implement
#	the given interface
#
package EBox::LogObserver;

use strict;
use warnings;

sub new 
{
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

# Method: domain
# 	
# 	Must return the text domain which the package belongs to
#
sub domain 
{
	throw EBox::Exceptions::NotImplemented;
}

# Method: logHelper 
#
# Returns:
#
#       An object implementing EBox::LogHelper
sub logHelper 
{
	return undef;
}

# Method: enableLog
#
#   This method must be overriden by the class implementing this interface,
#   if it needs to enable or disable logging facilities in the services its
#   managing.
#
# Parameters:
#
#   enable - boolean, true if it's enabled, false it's disabled
#
sub enableLog 
{
}

# Method: tableInfo
#
#	This function returns a hash ref with these parameters.
#	 - name: A string with the module name.
#	 - titles: A hash ref with the table fields and theirs user read
#	 	translation.
#	 - order: An array with table fields ordered.
#	 - tablename: the name of the database table associated with the module.
#	 - timecol: the table field that contains timestamp value (time and date
#	 field)
#
#	hours - The hash ref.
sub tableInfo
{
	throw EBox::Exceptions::NotImplemented;
}

# Method: humanEventMessage
#
#      Given a row with the table description given by
#      <EBox::LogObserver::tableInfo> it will return a human readable
#      message to inform admin using events.
#
#      To be overriden by subclasses. Default behaviour is showing
#      every field name following by a colon and the value.
#
# Parameters:
#
#      row - hash ref the row returned by <EBox::Logs::search>
#
# Returns:
#
#      String - the i18ned human readable message to send in an event
#
sub humanEventMessage
{
    my ($self, $row) = @_;

    my $tableInfo = $self->tableInfo();
    my $message = q{};
    foreach my $field (@{$tableInfo->{order}}) {
        if ( $field eq $tableInfo->{eventcol} ) {
            $message .= $tableInfo->{titles}->{$tableInfo->{eventcol}}
              . ': ' . $tableInfo->{events}->{$row->{$field}} . ' ';
        } else {
            my $rowContent = $row->{$field};
            # Delete trailing spaces
            $rowContent =~ s{ \s* \z}{}gxm;
            $message .= $tableInfo->{titles}->{$field} . ": $rowContent ";
        }
    }
    return $message;

}

1;
