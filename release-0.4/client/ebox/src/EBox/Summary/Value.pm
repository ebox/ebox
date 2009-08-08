# Copyright (C) 2004  Warp Netwoks S.L.
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

package EBox::Summary::Value;

use strict;
use warnings;

use base 'EBox::Summary::Item';
use EBox::Gettext;

sub new  # (key, value)
{
	my $class = shift;
	my $self = $class->SUPER::new();
	$self->{key} = shift;
	$self->{value} = shift;
	bless($self, $class);
	return $self;
}

sub html($) 
{
	my $self = shift;
	print '<tr>';
	print '<td class="summaryKey">';
	print $self->{key};
	print '</td>';
	print '<td class="summaryValue">';
	print $self->{value};
	print '</td>';
	print '</tr>';
	$self->_htmlitems;
}

1;
