# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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

package EBox::CGI::Software::InstallPkgs;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Gettext;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{domain} = 'ebox-software';
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $software = EBox::Global->modInstance('software');
	my $action = 'install';

	if (defined($self->param('upgrade'))) {
		$self->{chain} = "Software/Updates";
	} elsif (defined($self->param('ebox-install'))) {
		$self->{chain} = "Software/EBox";
	} elsif (defined($self->param('ebox-remove'))) {
		$self->{chain} = "Software/EBox";
		$action = 'remove';
	} else {
		$self->{redirect} = "Summary/Index";
		return;
	}

	my @pkgs = grep(s/^pkg-//, @{$self->params()});
	(@pkgs == 0) and return;
	if ($action eq 'install') {
		$software->installPkgs(@pkgs);
		$self->{msg} = __('The packages were installed successfully');
	} else {
		$software->removePkgs(@pkgs);
		$self->{msg} = __('The packages were uninstalled successfully');
	}
}

1;
