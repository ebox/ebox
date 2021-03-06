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

package EBox::UserCorner::CGI::CaptivePortal::PopUp;

use strict;
use warnings;

use base 'EBox::CGI::ClientRawBase';

use EBox::Global;
use EBox::Gettext;
use Error qw(:try);

sub new # (cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Captive Portal'),
        'template' => '/captiveportal/popup.mas',
        @_);
	$self->{domain} = 'ebox-captiveportal';
	bless($self, $class);
	return $self;
}

sub _process
{
    my $self = shift;
    my $captiveportal = EBox::Global->modInstance('captiveportal');
    $captiveportal->refresh();
    $self->{params} = $self->masonParameters();
}

sub masonParameters
{
    my ($self) = @_;

    my $captiveportal = EBox::Global->modInstance('captiveportal');

    my @params = ();
    push(@params, 'interval' => $captiveportal->interval());
    return \@params;
}

1;
