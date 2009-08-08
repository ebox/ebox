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

=head1 NAME

EBox::SysInfo - EBOX Miscellaneous system information module

=head1 DESCRIPTION

This module is used to display and set miscellaneous system information

=cut

package EBox::SysInfo;

use strict;
use warnings;

use base 'EBox::Module';

use Sys::Hostname;
use Sys::CpuLoad;
use Sys::CPU;
use POSIX qw(strftime);

use EBox::Config;
use EBox::Gettext;

=head1 METHODS

=cut

sub _create {
	my $class = shift;
	my $self =$class->SUPER::_create(name => 'sysinfo');
	bless($self, $class);
	return $self;
}

sub summary($) {
	my $self = shift;
	my $item = new EBox::Summary::Module(__("General information"));
	my $time = strftime("%a %b %e %H:%M:%S %Y", localtime);

	my $section = new EBox::Summary::Section();
	$item->add($section);
	$section->add(new EBox::Summary::Value(__("Time"), $time));
	$section->add(new EBox::Summary::Value(__("Host name"), hostname));
	$section->add(new EBox::Summary::Value(
		__("EBox version"),
		EBox::Config::version));
	$section->add(new EBox::Summary::Value(
		__("System load"), join(', ', Sys::CpuLoad::load)));
	return $item;
}

1;
