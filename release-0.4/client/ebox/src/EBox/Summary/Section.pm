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

package EBox::Summary::Section;

use strict;
use warnings;

use base 'EBox::Summary::Item';
use EBox::Gettext;

sub new # (title?)
{
	my $class = shift;
	my $self = $class->SUPER::new();
	$self->{title} = shift;
	bless($self, $class);
	return $self;
}

sub html
{
	my $self = shift;
	print '<table class="summarySection">';
	if ($self->{title}) {
		print '<caption>';
		print $self->{title};
		print '</caption>';
	}
	print '<tbody>';
	$self->_htmlitems;
	print '</tbody>';
	print '</table>';
}

1;
