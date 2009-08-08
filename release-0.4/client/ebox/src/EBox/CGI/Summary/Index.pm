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

package EBox::CGI::Summary::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Gettext;
use EBox::Global;
use EBox::Summary::Page;

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	return $self;
}

sub _body
{
	my $self = shift;
	$self->SUPER::_body;
	my $global = EBox::Global->getInstance();
	my @names = @{$global->modNames};
	my $page = new EBox::Summary::Page(__('Summary'));
	foreach (@names) {
		my $mod = EBox::Global->modInstance($_);
		settextdomain($mod->domain);
		my $item = $mod->summary;
		defined($item) or next;
		$page->add($item);
	}
	$page->html;
}

1;
