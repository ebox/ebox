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

package EBox::CGI::Network::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Network',
				      'template' => '/network/index.tmpl',
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
		$iflist[$i]->{'external'} = $net->ifaceIsExternal($_);
		if ($net->ifaceMethod($_) eq 'static') {
			$iflist[$i]->{'address'} = $net->ifaceAddress($_);
			$iflist[$i]->{'netmask'} = $net->ifaceNetmask($_);
		}
		$i++;
	}


	my @array = ();
	push(@array, {'iflist' => \@iflist});

	my $dns = $net->nameserverOne();
	defined($dns) or $dns = "";
	push(@array, {'dnsone' => $dns});

	$dns = $net->nameserverTwo();
	defined($dns) or $dns = "";
	push(@array, {'dnstwo' => $dns});

	$dns = $net->nameserverThree();
	defined($dns) or $dns = "";
	push(@array, {'dnsthree' => $dns});

	push(@array, {'gateway' => $net->gateway});

	my $routes = $net->routes;
	defined($routes) and push(@array, {'routes' =>  $net->routes});

	$self->{params} = \@array;
}

1;
