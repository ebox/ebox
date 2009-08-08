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

package EBox::CGI::Network::VIface;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

sub new # (cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Network/Ifaces";
	bless($self, $class);
	return $self;
}

sub _process
{
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	$self->_requireParam("ifname", __("network interface"));
	$self->_requireParam("ifaction", __("virtual interface action"));

	my $iface = $self->param("ifname");
	my $ifaction = $self->param("ifaction");
	
	if ($ifaction eq 'add'){
		$self->_requireParam("vif_address", __("IP address"));
		$self->_requireParam("vif_netmask", __("netmask"));
		$self->_requireParam("vif_name", __("virtual interface name"));
		my $name = $self->param("vif_name");
		my $address = $self->param("vif_address");
		my $netmask = $self->param("vif_netmask");
		$net->setViface($iface, $name, $address,  $netmask);
	} elsif ($ifaction eq 'delete')  {
		$self->_requireParam("vif_name", __("virtual interface name"));
		my $viface = $self->param("vif_name");
		$net->removeViface($iface, $viface);
	}

}
1;
