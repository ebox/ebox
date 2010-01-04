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

# Interface class EBox::HtmlBlocks, it should be implemented by CGI namespaces
#
# This file defines the interface and gives the implementation for the EBox
# namespace
package EBox::HtmlBlocks;

use strict;
use warnings;

use EBox::Html;

sub new
{
    my $class = shift;
    my $self = {};
    bless($self, $class);
    return $self;
}

# Method: title
#
#	Returns the html code for the title
#
# Returns:
#
#      	string - containg the html code for the title
#
sub title
{
    return EBox::Html::title();
}

# Method: menu
#
#	Returns the html code for the menu
#
# Returns:
#
#      	string - containg the html code for the menu
#
sub menu
{
    my ($self, $current) = @_;
    return EBox::Html::menu($current);
}

# Method: footer
#
#	Returns the html code for the footer page
#
# Returns:
#
#      	string - containg the html code for the footer page
#
sub footer
{
    return EBox::Html::footer();
}

1;
