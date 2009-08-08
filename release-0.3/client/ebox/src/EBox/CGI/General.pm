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

package EBox::CGI::General;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;
use POSIX qw(setlocale LC_ALL);

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('General configuration'),
				      'template' => '/general.mas',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;

	my $global = EBox::Global->getInstance();
	my $apache = $global->modInstance('apache');

	my @array = ();
	push(@array, 'port' => $apache->port());
	push(@array, 'lang' => $global->locale());

	$self->{params} = \@array;
}

1;
