# Copyright (C) 2008 eBox Technologies S.L.
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

package EBox::CGI::Printers::LPDPrinterUI;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Gettext;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title'    => __('Add a new printer (II)'),
				      'template' => 'printers/lpd.mas',
				      @_);
	$self->{domain} = 'ebox-printers';
	bless($self, $class);
	return $self;
}

sub domain
{
	return 'ebox-printers';
}

sub _process($) {
	my $self = shift;

	$self->_requireParam('printerid', __('Printer'));
	my $id = $self->param('printerid');

	my $printers = EBox::Global->modInstance('printers');

	my @array;
        push (@array, 'printerid' => $id);
	push (@array, 'button_val' => __('Next'));
	push (@array, 'button_name' => 'lpdconfui');
	$self->{params} = \@array;
}

1;
