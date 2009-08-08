package EBox::CGI::Firewall::ObjectPolicy;

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
	return $self;
}

sub _process($) {
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');

	$self->{errorchain} = "Firewall/Index";
	$self->_requireParam('object', __('Object'));
	$self->{errorchain} = "Firewall/Index?object=". $self->param("object");
	$self->_requireParam('policy', __('policy'));

	$self->{redirect} = "Firewall/Object?object=" . $self->param("object");
	$firewall->setObjectPolicy($self->param("object"), $self->param("policy"));
}

1;
