package EBox::CGI::Summary::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

use EBox::SysInfo;
use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	return $self;
}

sub _body($) {
	my $self = shift;
	$self->SUPER::_body;
	my $global = EBox::Global->modInstance('global');
	my @names = $global->modNames;
	foreach (@names) {
		my $mod = EBox::Global->modInstance($_);
		my $item = $mod->summary;
		defined($item) or next;
		$item->html;
	}
}

1;
