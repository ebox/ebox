# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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

# Method: loglHelper 
#
# Returns:
#
#       An object implementing EBox::LogHelper
sub logHelper 
{
	return undef;
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

1;
