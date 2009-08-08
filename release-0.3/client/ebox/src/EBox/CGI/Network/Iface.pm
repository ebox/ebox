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

package EBox::CGI::Network::Iface;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Network/Ifaces";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	$self->_requireParam("method", __("method"));
	$self->_requireParam("ifname", __("network interface"));

	my $iface = $self->param("ifname");
	my $method = $self->param("method");
	my $external = undef;
	if (defined($self->param('external'))) {
		$external = 1;
	}

	if ($method eq 'static') {
		$self->_requireParam("if_address", __("ip address"));
		$self->_requireParam("if_netmask", __("netmask"));
		my $address = $self->param("if_address");
		my $netmask = $self->param("if_netmask");
		$net->setIfaceStatic($iface, $address, $netmask, $external);
	} elsif ($method eq 'dhcp') {
		$net->setIfaceDHCP($iface, $external);
	} elsif ($method eq 'notset') {
		$net->unsetIface($iface);
	}
}

1;
