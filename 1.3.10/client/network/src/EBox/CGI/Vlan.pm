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

package EBox::CGI::Network::Vlan;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;
use Error qw(:try);

sub new # (cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{domain} = 'ebox-network';
	bless($self, $class);
	return $self;
}

sub _process
{
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	$self->_requireParam("ifname", __("network interface"));
	my $iface = $self->param("ifname");
        $self->_requireParam("vlanid", __("VLAN Id"));
        my $vlanId = $self->param('vlanid');

	$self->{redirect} = "Network/Ifaces?iface=$iface";
	$self->{errorchain} = "Network/Ifaces";

	$self->keepParam('iface');
	$self->cgi()->param(-name=>'iface', -value=>$iface);

        if ($self->param('cancel')) {
            return;
        }


	if (defined($self->param('del'))) {
            try {
                my $force = $self->param('force');
                $net->removeVlan($vlanId, $force);
           } catch EBox::Exceptions::DataInUse with {
               $self->{template} = 'network/confirmVlanDel.mas';
               $self->{redirect} = undef;
               my @masonParams = ();
               push@masonParams, ('iface' => $iface);
               push @masonParams, (vlanid => $vlanId);
               $self->{params} = \@masonParams;
           };

	} elsif (defined($self->param('add'))) {
		$net->createVlan($vlanId,
				 $self->param('vlandesc'),
				 $iface);
	}
}

1;
