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

package EBox::Network::Model::GatewayDataTable;

use EBox::Global;
use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Exceptions::External;

use EBox::Types::Int;
use EBox::Types::Text;
use EBox::Types::Boolean;
use EBox::Types::Select;
use EBox::Types::IPAddr;
use EBox::Types::Union;
use EBox::Sudo;

use Net::ARP;

use strict;
use warnings;


use base 'EBox::Model::DataTable';

use constant MAC_FETCH_TRIES => 3;


sub new 
{
	my $class = shift;
	my %parms = @_;
	
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	
	return $self;
}

sub selectOptions
{
	my ($self, $id) = @_;
	
	if ($id eq 'interface') {
		my $network = EBox::Global->modInstance('network');
		my @ifaces = (@{$network->InternalIfaces()}, 
			      @{$network->ExternalIfaces()});
		      
		my @options = map { 'value' => $_, 
				     'printableValue' => $_ }, @ifaces;

		return \@options;
	} elsif ($id eq 'weight') {
		my @options;
		for my $weight (1..15) {
			push @options, { 'value' => $weight, 
					 'printableValue' => $weight};
		}
		return \@options;
	}
}

sub _table
{
	my @tableHead = 
	 ( 

		new EBox::Types::Text(
					'fieldName' => 'name',
					'printableName' => __('Name'),
					'class' => 'tcenter',
					'type' => 'text',
					'size' => '12',
					'unique' => 1,
					'editable' => 1
				      ),
		new EBox::Types::Text(
					'fieldName' => 'ip',
					'printableName' => __('IP Address'),
					'class' => 'tcenter',
					'type' => 'text',
					'size' => '16',
					'unique' => 1,
					'editable' => 1
				      ),
		new EBox::Types::Select(
					'fieldName' => 'interface',
					'printableName' => __('Interface'),
					'class' => 'tcenter',
					'type' => 'select',
					'size' => '16',
					'unique' => 0,
					'editable' => 1
				),
		new EBox::Types::Int(
					'fieldName' => 'upload',
					'printableName' => __('Upload'),
					'class' => 'tcenter',
					'type' => 'int',
					'size' => '3',
					'unique' => 0,
					'editable' => 1,
					'trailingText' => 'Kb/s'
				),
		new EBox::Types::Int(
					'fieldName' => 'download',
					'printableName' => __('Download'),
					'class' => 'tcenter',
					'type' => 'int',
					'size' => '3',
					'unique' => 0,
					'editable' => 1,
					'trailingText' => 'Kb/s'
				),
		new EBox::Types::Select(
					'fieldName' => 'weight',
					'printableName' => __('Weight'),
					'class' => 'tcenter',
					'type' => 'select',
					'size' => '2',
					'unique' => 0,
					'editable' => 1
				),
		new EBox::Types::Boolean(
					'fieldName' => 'default',
					'printableName' => __('Default'),
					'class' => 'tcenter',
					'type' => 'boolean',
					'size' => '1',
					'unique' => 0,
					'trailingText' => '',
					'editable' => 1
				)

	 );

	my $dataTable = 
		{ 
			'tableName' => 'gatewaytable',
			'printableTableName' => __('Gateway list'),
			'actions' =>
				{
				'add' => 
				  '/ebox/Network/Controller/GatewayDataTable', 
				'del' => 
				  '/ebox/Network/Controller/GatewayDataTable', 
				'move' => 
				  '/ebox/Network/Controller/GatewayDataTable', 
				'editField' => 
				  '/ebox/Network/Controller/GatewayDataTable', 
				'changeView' =>
				  '/ebox/Network/Controller/GatewayDataTable', 
				},
			'tableDescription' => \@tableHead,
			'class' => 'dataTable',
			'order' => 0,
			'help' => __x('You can add as many gateways as you want. This is very useful if you want to split your Internet traffic through several links.{br}The download and upload fields must be set as much rate as you have to your connection towards the gateway. The correct value of these fields is critical to ensure a correct functionality of the traffic shaping module', br => '<br>'),
		        'rowUnique' => 0,
		        'printableRowName' => __('gateway'),
		};

	return $dataTable;
}

# Method: validateRow
#
#      Override <EBox::Model::DataTable::validateRow> method
#
sub validateRow()
{
	my $self = shift;
	my $action = shift;
	my %params = @_;

	my $network = EBox::Global->modInstance('network');
	checkIP($params{'ip'}, __("ip address"));
	$network->_gwReachable($params{'ip'}, 'LaunchException');

	return unless ($params{'default'});

	# Check if there's only one default gw
	my $currentRow = $params{'id'};
	foreach my $row (@{$self->rows()}) {
		if (defined($currentRow) and $currentRow eq $row->{'id'}) {
			next;
		}
		foreach my $value (@{$row->{'values'}}) {
			next unless ($value->fieldName() eq 'default');
			if ($value->printableValue() == 1) {
				throw EBox::Exceptions::External(
			         __('There is already a default gateway'));

			}
		}
	}
}

sub defaultGateway()
{
	my $self = shift;

	for my $row (@{$self->rows()}) {
		my $default = $row->{'valueHash'}->{'default'};
		next unless ($default->printableValue() eq 1);
		my $ip = $row->{'valueHash'}->{'ip'};
		return $ip->printableValue();
	}

	return undef;
}

sub iproute2TableIds()
{
	my $self = shift;

	my @ids;
	for my $row (@{$self->rows()}) {
		push (@ids, $row->{'id'});
	}

	return \@ids;
}

sub marksForRouters()
{
	my $self = shift;

	my $ids = $self->iproute2TableIds();

	my $marks;
	my $i = 1;
	for my $id (@{$ids}) {
		$marks->{$id} = $i;
		$i++;
	}
	
	return $marks;
}

sub gateways()
{
	my $self = shift;

	my @gateways;
	for my $row (@{$self->rows()}) {
		my $id = $row->{'id'};
		my $name = $row->{'valueHash'}->{'name'}->printableValue();
		my $ifce = $row->{'valueHash'}->{'interface'}->printableValue();
		my $ip = $row->{'valueHash'}->{'ip'}->printableValue();
		my $up = $row->{'valueHash'}->{'upload'}->printableValue();
		my $down = $row->{'valueHash'}->{'download'}->printableValue();
		my $weight = $row->{'valueHash'}->{'weight'}->printableValue();
		my $def = $row->{'valueHash'}->{'default'}->printableValue();
	
		push (@gateways, { 
					'id' => $id,
					'name' => $name, 
					'ip' => $ip,
					'interface' => $ifce,
					'upload' => $up,
					'download' => $down,
					'weight' => $weight,
					'default' => $def,
				});
	}

	return \@gateways;
}

sub gatewaysWithMac
{
	my ($self) = @_;

	my $gws = $self->gateways();

	foreach my $gw (@{$gws}) {
		
		$gw->{'mac'} = _getRouterMac($gw->{'ip'});
	}

	return $gws;
}

sub deletedRowNotify()
{
	my ($self, $row) = @_;

	my $network = EBox::Global->modInstance('network');
	my $multigwRules = $network->multigwrulesModel();
	$multigwRules->removeRulesUsingRouter($row->{'id'});
}

sub _getRouterMac
{
	my ($ip) = @_;
	my $macif = '';

	my $mac;
	for (0..MAC_FETCH_TRIES) {
		system("ping -c 1 -W 3 $ip");
		$mac = Net::ARP::arp_lookup($macif, $ip);
		return $mac if ($mac ne '00:00:00:00:00:00'); 
	}
	return $mac;
}

1;

