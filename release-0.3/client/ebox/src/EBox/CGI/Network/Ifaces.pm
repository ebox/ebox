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

package EBox::CGI::Network::Ifaces;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Interfaces'),
				      'template' => '/network/ifaces.mas',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	my $ifaces = $net->ifaces();
	my @iflist = ();
	my $i = 0;

	foreach (@{$ifaces}) {
		$iflist[$i]->{'name'} = $_;
		$iflist[$i]->{'method'} = $net->ifaceMethod($_);
		if ($net->ifaceIsExternal($_)){
			$iflist[$i]->{'external'} = "yes";
		} else {
			$iflist[$i]->{'external'} = "no";
		}
		if ($net->ifaceMethod($_) eq 'static') {
			$iflist[$i]->{'address'} = $net->ifaceAddress($_);
			$iflist[$i]->{'netmask'} = $net->ifaceNetmask($_);
			$iflist[$i]->{'virtual'} = $net->vifacesConf($_);
		}
		$i++;
	}


	my @array = ();
	push(@array, 'iflist' => \@iflist);

	$self->{params} = \@array;
}

1;
