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

package EBox::CGI::Squid::Transparent;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'squid',
				      @_);
	$self->{redirect} = "Squid/Index";	
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $squid = EBox::Global->modInstance('squid');
	$self->_requireParam('active', __('Transparent Proxy Status'));
	$squid->setTransproxy($self->param("active"));
	
	
}

1;
