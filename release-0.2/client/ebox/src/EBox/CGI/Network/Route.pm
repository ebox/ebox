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

package EBox::CGI::Network::Route;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Network/Index";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	$self->_requireParam('ip', __('network address'));
	$self->_requireParam('mask', __('network mask'));
	
	if (defined($self->param('del'))) {
		$net->delRoute($self->param("ip"), $self->param("mask"));
	} elsif (defined($self->param('add'))) {
		$self->_requireParam('gateway', __('gateway address'));
		$net->addRoute( $self->param('ip'),
				$self->param('mask'),
				$self->param('gateway'));
	} elsif (defined($self->param('up'))) {
		$net->routeUp($self->param("ip"), $self->param("mask"));
	} elsif (defined($self->param('down'))) {
		$net->routeDown($self->param("ip"), $self->param("mask"));
	}
}

1;
