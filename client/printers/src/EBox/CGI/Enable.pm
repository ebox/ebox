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

package EBox::CGI::Printers::Enable;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Gettext;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Samba',
				      @_);
	$self->{redirect} = "Printers/ShowPrintersUI";	
	$self->{domain} = "ebox-printers";	
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $samba = EBox::Global->modInstance('printers');

	$self->_requireParam('active', __('module status'));
	$samba->setService(($self->param('active') eq 'yes'));
	
}

1;