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

package EBox::Network::Model::GatewayTable;

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

sub weights
{
	my @options;
	for my $weight (1..15) {
		push @options, { 'value' => $weight, 
				 'printableValue' => $weight};
	}
	return \@options;
}

sub interfaces
{
	my $network = EBox::Global->modInstance('network');
	my @ifaces = (@{$network->InternalIfaces()}, 
		      @{$network->ExternalIfaces()});
	      
	my @options = map { 'value' => $_, 
			     'printableValue' => $_ }, @ifaces;

	return \@options;
}

sub _table
{
	my @tableHead = 
	 ( 

		new EBox::Types::Text(
					'fieldName' => 'name',
					'printableName' => __('Name'),
					'size' => '12',
					'unique' => 1,
					'editable' => 1
				      ),
		new EBox::Types::Text(
					'fieldName' => 'ip',
					'printableName' => __('IP Address'),
					'size' => '16',
					'unique' => 1,
					'editable' => 1
				      ),
		new EBox::Types::Select(
					'fieldName' => 'interface',
					'printableName' => __('Interface'),
					'populate' => \&interfaces,
					'editable' => 1,
					'help' => __('Interface connected to this gateway')
				),
		new EBox::Types::Int(
					'fieldName' => 'upload',
					'printableName' => __('Upload'),
					'size' => '3',
					'editable' => 1,
					'trailingText' => 'Kb/s',
					'help' => __('Upload rate in Kbits/s for this gateway.')
								
				),
		new EBox::Types::Int(
					'fieldName' => 'download',
					'printableName' => __('Download'),
					'size' => '3',
					'editable' => 1,
					'trailingText' => 'Kb/s',
					'help' => __('Download rate in Kbits/s for this gateway.')
				),
		new EBox::Types::Select(
					'fieldName' => 'weight',
					'printableName' => __('Weight'),
					'size' => '2',
					'populate' => \&weights,
					'editable' => 1,
					'help' => __('This field is only useful if you have ' . 
								 'more than one router and  the balance ' .
								 'traffic feature is enabled.')
				),
		new EBox::Types::Boolean(
					'fieldName' => 'default',
					'printableName' => __('Default'),
					'size' => '1',
					'editable' => 1,
				)

	 );

	my $dataTable = 
		{ 
			'tableName' => 'GatewayTable',
			'printableTableName' => __('Gateway list'),
			'automaticRemove' => 1,
			'defaultController' =>
				'/ebox/Network/Controller/GatewayTable',
			'defaultActions' =>
				[	
				'add', 'del',
				'move',  'editField',
				'changeView'
				],
			'tableDescription' => \@tableHead,
			'menuNamespace' => 'Network/View/GatewayTable',
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
	$network->gatewayReachable($params{'ip'}, 'LaunchException');

	return unless ($params{'default'});

	# Check if there's only one default gw
	my $currentRow = $params{'id'};
	my $defaultRow = $self->find('default' => 1);
	if (defined($defaultRow) and ($currentRow ne $defaultRow->id())) {
		my $default = $defaultRow->elementByName('default');
		$default->setValue(undef);
		$defaultRow->storeElementByName('default');
	}
}

sub defaultGateway()
{
	my $self = shift;

	my $default = $self->find('default' => 1);
	if ($default) {
		return $default->valueByName('ip');
	} else {
		return undef;
	}
}

sub iproute2TableIds()
{
	my $self = shift;

	my @ids;
	for my $row (@{$self->rows()}) {
		push (@ids, $row->id());
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

	foreach my $gw (@{$self->rows()}) {
		push (@gateways, {
							id => $gw->id(),
							name => $gw->valueByName('name'),
							ip => $gw->valueByName('ip'),
							weight => $gw->valueByName('weight'),
							default => $gw->valueByName('default'),
							upload => $gw->valueByName('upload'),
							download => $gw->valueByName('download'),
							interface => $gw->valueByName('interface'),
						 });
	}

	return \@gateways;
}

sub gatewaysWithMac
{
	my ($self) = @_;

	my @gateways = @{$self->gateways()};
	foreach my $gw (@gateways) {
		$gw->{'mac'} = _getRouterMac($gw->{'ip'});
	}

	return \@gateways;
}

sub _getRouterMac
{
	my ($ip) = @_;
	my $macif = '';

	my $mac;
	for (0..MAC_FETCH_TRIES) {
		system("ping -c 1 -W 3 $ip  > /dev/null 2> /dev/null");
		$mac = Net::ARP::arp_lookup($macif, $ip);
		return $mac if ($mac ne '00:00:00:00:00:00'); 
	}
	return $mac;
}

1;

