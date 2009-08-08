package EBox::CGI::Firewall::ObjectService;

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
	$self->{redirect} = "Firewall/Object?object=". $self->param("object");


	if (defined($self->param('add')) || defined($self->param('change'))) {
		$self->_requireParam('service', __('service'));
		$self->_requireParam('policy', __('policy'));
		$firewall->setObjectService($self->param("object"),
					 $self->param("service"),
					 $self->param("policy"));
	} elsif (defined($self->param('delete'))) {
		$self->_requireParam('service', __('service'));
		$firewall->removeObjectService($self->param("object"),
					    $self->param("service"));
	}

}

1;
