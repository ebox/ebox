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

package EBox::Sudo;

use strict;
use warnings;

use EBox::Config;
use EBox::Exceptions::Internal;
use EBox::Gettext;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS  = (all => [qw{ root } ],
			);
	@EXPORT_OK = qw();
	Exporter::export_ok_tags('all');
	$VERSION = EBox::Config::version;
}

sub root($) {
	my $cmd = shift;
	unless (system("/usr/bin/sudo " . $cmd) == 0) {
		throw EBox::Exceptions::Internal(__x("Root command '{cmd}' failed", cmd => $cmd));
	}
}

sub sudo($$) {
	my ($cmd, $user) = @_;
	unless (system("/usr/bin/sudo -u " . $user . " " . $cmd) == 0) {
		throw EBox::Exceptions::Internal(__x("Running command '{cmd}' as {user} failed", cmd => $cmd, user => $user));
	}
}

1;
