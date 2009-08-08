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

package EBox::CGI::Network::Nameservers;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Gettext;
use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Network/DNS";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	my $dns1 = $self->param("dnsone");
	my $dns2 = $self->param("dnstwo");
	my $dns3 = $self->param("dnsthree");

	$dns1 =~ s/^\s+|\s+$//g;
	$dns2 =~ s/^\s+|\s+$//g;
	$dns3 =~ s/^\s+|\s+$//g;

	$net->setNameservers($dns1, $dns2, $dns3);
}

1;
