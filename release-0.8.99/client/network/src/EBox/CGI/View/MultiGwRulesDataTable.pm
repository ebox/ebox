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

package EBox::CGI::Network::View::MultiGwRulesDataTable;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;
use EBox;

sub new # (cgi=?)
{
	my $class = shift;

	my $self = $class->SUPER::new('title' => __('Multigateway rules'), 
				'template' => '/network/gwrules.mas',
				@_);
	$self->{domain} = 'ebox-network';
	
	bless($self, $class);
	return $self;
}

sub _process
{
	my $self = shift;
	my $network = EBox::Global->modInstance('network');
	my $model = $network->multigwrulesModel();
	my @gateways = @{$network->gateways()};

	my @params;
	push(@params, 'data' => $model->rows());
	push(@params, 'dataTable' => $model->tableInfo());
	
	my $routersAvailable = 0;
	if (@gateways > 1) {
		$routersAvailable = 1;
	}
	push(@params, 'routersAvailable' => $routersAvailable);

	$self->{'params'} = \@params;

	
}

1;
