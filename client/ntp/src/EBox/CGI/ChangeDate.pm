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

package EBox::CGI::NTP::ChangeDate;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Gettext;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'NTP', @_);
	$self->{redirect} = "NTP/ChangeDate";	
	$self->{domain} = "ebox-ntp";	
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $ntp= EBox::Global->modInstance('ntp');
	
	$self->_requireParam('day', __('Day'));
	$self->_requireParam('month', __('Month'));
	$self->_requireParam('year', __('Year'));
	$self->_requireParam('hour', __('Hour'));
	$self->_requireParam('minute', __('Minutes'));
	$self->_requireParam('second', __('Seconds'));
	
	my $day = $self->param('day');
	my $month = $self->param('month');
	my $year = $self->param('year');
	my $hour = $self->param('hour');
	my $minute = $self->param('minute');
	my $second = $self->param('second');
	
	$ntp->setNewDate($day, $month, $year, $hour, $minute, $second);
}

1;
