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

package EBox::SysInfo;

use strict;
use warnings;

use base qw(EBox::Module EBox::Report::DiskUsageProvider);

use Sys::Hostname;
use Sys::CpuLoad;

use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Summary::Module;
use EBox::Summary::Section;
use EBox::Summary::Value;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::Report::RAID;


sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'sysinfo',
                                          printableName => __('system information'),
                                          @_);
	bless($self, $class);
	return $self;
}


sub _facilitiesForDiskUsage
{
  my ($self, @params) = @_;
  return EBox::Backup->_facilitiesForDiskUsage(@params);
}

#
# Method: summary
#
#   	Overriden method that returns summary components 
#   	for system information
#

sub summary
{
	my $self = shift;
	my $item = new EBox::Summary::Item;
	my $global = EBox::Global->getInstance(1);
	my @names = @{$global->modNames};
	my $services = 0;
	my $module = new EBox::Summary::Module(__("Services"));
	my $section = new EBox::Summary::Section();
	
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

	my $time_command = "LC_TIME=" . EBox::locale() . " /bin/date";
	my $time = `$time_command`;
	
	$section->add(new EBox::Summary::Value(__("Time"), $time));
	$section->add(new EBox::Summary::Value(__("Host name"), hostname));
	$section->add(new EBox::Summary::Value(
		__("eBox version"),
		EBox::Config::version));
	$section->add(new EBox::Summary::Value(
		__("System load"), join(', ', Sys::CpuLoad::load)));
	return $item;
}

#
# Method: menu
#
#   	Overriden method that returns the core menu entries: 
#		
#	- Summary
#	- Save/Cancel
#	- Logout
#	- EBox/General
#	- EBox/Backup
#	- EBox/Halt
#	- EBox/Bug
sub menu
{
	my ($self, $root) = @_;

	$root->add(new EBox::Menu::Item('url' => 'Summary/Index',
					'text' => __('Summary'),
					'order' => 1));

	$root->add(new EBox::Menu::Item('url' => 'ServiceModule/StatusView',
					'text' => __('Module status'),
					'order' => 2));


	my $folder = new EBox::Menu::Folder('name' => 'EBox',
					    'text' => __('System'),
					    'order' => 3);

	$folder->add(new EBox::Menu::Item('url' => 'EBox/General',
					  'text' => __('General')));

	$folder->add(new EBox::Menu::Item('url' => 'Report/DiskUsage',
					  'text' => __('Disk usage Information')));
	if (EBox::Report::RAID::enabled()) {
	$folder->add(new EBox::Menu::Item(
			 'url' => 'Report/RAID',
           		 'text' => __('RAID Information'))
		    );
	}


	$folder->add(new EBox::Menu::Item('url' => 'EBox/Backup',
					  'text' => __('Backup')));

	$folder->add(new EBox::Menu::Item('url' => 'EBox/Halt',
					  'text' => __('Halt/Reboot')));

	$folder->add(new EBox::Menu::Item('url' => 'EBox/Bug',
					  'text' => __('Bug report')));



	$root->add($folder);
}

1;
