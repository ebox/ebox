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

package EBox::CGI::Network::DNS;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'DNS',
				      'template' => '/network/dns.mas',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	my @array = ();

	my $dns = $net->nameserverOne();
	defined($dns) or $dns = "";
	push(@array, 'dnsone' => $dns);

	$dns = $net->nameserverTwo();
	defined($dns) or $dns = "";
	push(@array, 'dnstwo' => $dns);

	$dns = $net->nameserverThree();
	defined($dns) or $dns = "";
	push(@array, 'dnsthree' => $dns);

	$self->{params} = \@array;
}

1;
