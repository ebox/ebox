package EBox::CGI::Objects::DelFrom;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	$self->{redirect} = "/Objects/Index";
	return $self;
}

sub _process($) {
	my $self = shift;
	my $objects = EBox::Global->modInstance('objects');

	$self->_requireParam('objectname', __('Object name'));
	$self->_requireParam('ip_addr', __('IP address'));
	$self->_requireParam('ip_mask', __('Mask'));

	$objects->delFromObject($self->param("objectname"),
				$self->param("ip_addr"),
				$self->param("ip_mask"));
	$self->{redirect} = "/Objects/Index?show=" . $self->param("objectname");
}

1;
