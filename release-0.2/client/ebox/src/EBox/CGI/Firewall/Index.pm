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

package EBox::CGI::Firewall::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Firewall;
use EBox::Objects;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Firewall'),
				      'template' => '/firewall/index.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');
	my $objects = EBox::Global->modInstance('objects');
	my $net = EBox::Global->modInstance('network');

	my $redirections = $firewall->portRedirections;
	my $objectlist = $objects->getObjectsArray();
	my $aux = $net->ifaces;
	my @ifaces = ();
	foreach(@{$aux}) {
		# FIXME do not allow redirections on internal interfaces that
		# are configured via dhcp
		push(@ifaces, {'name' => $_});
	}

	foreach (@{$objectlist}) {
		delete($_->{member});
	}

	my @array = ();

	if (defined($redirections)) {
		push(@array, {'redirections' => $redirections});
	}

	push(@array, {'ifaces' => \@ifaces});
	push(@array, {'deny' => $firewall->denyAction});
	if ($objectlist && length(@{$objectlist}) > 0) {
		push(@array, {'objects' => $objectlist});
	}
	$self->{params} = \@array;
}

1;
