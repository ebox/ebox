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
use Sys::CPU;
use Sys::Load;


use EBox::Exceptions::Unknown;
use EBox::Config;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

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

	my $section = new EBox::Summary::Section(__("System"));
	$item->add($section);
	$section->add(new EBox::Summary::Value(__("Host name"), hostname));
	$section->add(new EBox::Summary::Value(__("Uptime"), Sys::Load::uptime));
	$section->add(new EBox::Summary::Value(__("Load"), Sys::Load::getload));

	$section = new EBox::Summary::Section(__("CPU"));
	$item->add($section);
	$section->add(new EBox::Summary::Value(__("Number"), Sys::CPU::cpu_count));
	$section->add(new EBox::Summary::Value(__("Type"), Sys::CPU::cpu_type));
	$section->add(new EBox::Summary::Value(__("Speed"), Sys::CPU::cpu_clock));

	return $item;
}

1;
