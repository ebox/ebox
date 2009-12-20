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

# Class: EBox::LogHelper
#
#       This class exposes the interface to be implemented by those
#       modules willing to process logs generated by their daemon or service.
#       An instance of this class must be returned inheriting from
#       EBox::LogObserver and implementing the method logHelper()
#
package EBox::LogHelper;

use strict;
use warnings;

sub new
{
    my $class = shift;
    my $self = {};
    bless($self, $class);
    return $self;
}

# Method: logFiles
#
#       This function must return the file or files to be read from.
#
# Returns:
#
#       array ref - containing the whole paths
#
sub logFiles
{
    return [];
}

# Method: processLine
#
#       This function will be run every time a new line is received in
#       the associated file. You must parse the line, and generate
#       the messages which will be logged to eBox through an object
#       implementing <EBox::AbstractLogger> interface.
#
# Parameters:
#
#       file - file name
#       line - string containing the log line
#       dbengine - An instance of class implemeting AbstractDBEngine interface
#
sub processLine # (file, line, dbengine)
{
    return undef;
}


1;
