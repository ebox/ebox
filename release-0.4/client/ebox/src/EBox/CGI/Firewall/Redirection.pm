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

package EBox::CGI::Firewall::Redirection;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

sub new # (cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	$self->{redirect} = "Firewall/Redirects";
	return $self;
}

sub _process
{
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');

	if (defined($self->param('add'))) {
		$self->_requireParam('proto', __('protocol'));
		$self->_requireParam('iface', __('network interface'));
		$self->_requireParam('eport', __('external port'));
		$self->_requireParam('address', __('destination address'));
		$self->_requireParam('dport', __('destination port'));
		$firewall->addPortRedirection($self->param("proto"),
					      $self->param("eport"),
					      $self->param("iface"),
					      $self->param("address"),
					      $self->param("dport"));
	} elsif (defined($self->param('delete'))) {
		$self->_requireParam('oldproto', __('protocol'));
		$self->_requireParam('oldeport', __('external port'));
		$self->_requireParam('oldiface', __('network interface'));
		$firewall->removePortRedirection($self->param("oldproto"),
						 $self->param("oldeport"),
						 $self->param("oldiface"));
	} elsif (defined($self->param('change'))) {
		$self->_requireParam('oldproto', __('protocol'));
		$self->_requireParam('oldeport', __('external port'));
		$self->_requireParam('oldiface', __('network interface'));
		$self->_requireParam('iface', __('network interface'));
		$self->_requireParam('proto', __('protocol'));
		$self->_requireParam('eport', __('external port'));
		$self->_requireParam('address', __('destination address'));
		$self->_requireParam('dport', __('destination port'));
		$firewall->removePortRedirection($self->param("oldproto"),
						 $self->param("oldeport"),
						 $self->param("oldiface"));

		$firewall->addPortRedirection($self->param("proto"),
					      $self->param("eport"),
					      $self->param("iface"),
					      $self->param("address"),
					      $self->param("dport"));
	}

}

1;
