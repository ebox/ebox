# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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

package EBox::CGI::Network::Ifaces;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Network interfaces'),
				      'template' => '/network/ifaces.mas',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process
{
	my $self = shift;
	my $net = EBox::Global->modInstance('network');
	my $ifname = $self->param('iface');
	($ifname) or $ifname = '';

	my $ifaces = $net->ifaces();
	my $iface = {};
	if ($ifname eq '') {
		$ifname = @{$ifaces}[0];
	}

	foreach (@{$ifaces}) {
		($_ eq $ifname) or next;
		$iface->{'name'} = $_;
		$iface->{'method'} = $net->ifaceMethod($_);
		if ($net->ifaceIsExternal($_)){
			$iface->{'external'} = "yes";
		} else {
			$iface->{'external'} = "no";
		}
		if ($net->ifaceMethod($_) eq 'static') {
			$iface->{'address'} = $net->ifaceAddress($_);
			$iface->{'netmask'} = $net->ifaceNetmask($_);
			$iface->{'virtual'} = $net->vifacesConf($_);
		}
	}


	my @array = ();
	push(@array, 'iface' => $iface);
	push(@array, 'ifaces' => $ifaces);

	$self->{params} = \@array;
}

1;
