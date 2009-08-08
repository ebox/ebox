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

package EBox::SysInfo;

use strict;
use warnings;

use base 'EBox::Module';

use Sys::Hostname;
use Sys::CpuLoad;

use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Summary::Module;
use EBox::Summary::Section;
use EBox::Summary::Value;

sub _create 
{
	my $class = shift;
	my $self =$class->SUPER::_create(name => 'sysinfo', @_);
	bless($self, $class);
	return $self;
}

sub summary
{
	my $self = shift;
	my $item = new EBox::Summary::Item;
	my $global = EBox::Global->getInstance;
	my @names = @{$global->modNames};
	my $services = 0;
	my	$module = new EBox::Summary::Module(__("Services"));
	my	$section = new EBox::Summary::Section();
	
	foreach (@names) {
		my $mod = $global->modInstance($_);
		my $status = $mod->statusSummary;
		if (defined($status)) {
			$services = 1;
			$section->add($status);
		}
	}

	if($services == 1) {
		$item->add($module);
		$module->add($section);
	}

	$module = new EBox::Summary::Module(__("General information"));
	$item->add($module);
	$section = new EBox::Summary::Section();
	$module->add($section);

	my $time = `/bin/date`;
	
	$section->add(new EBox::Summary::Value(__("Time"), $time));
	$section->add(new EBox::Summary::Value(__("Host name"), hostname));
	$section->add(new EBox::Summary::Value(
		__("eBox version"),
		EBox::Config::version));
	$section->add(new EBox::Summary::Value(
		__("System load"), join(', ', Sys::CpuLoad::load)));
	return $item;
}

1;
