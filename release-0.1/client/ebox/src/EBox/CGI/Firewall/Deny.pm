package EBox::CGI::Firewall::Deny;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Firewall',
				      @_);
	bless($self, $class);
	$self->{redirect} = "Firewall/Index";
	return $self;
}

sub _process($) {
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');

	$self->_requireParam('deny', __('action'));
	$firewall->setDenyAction($self->param("deny"));

}

1;
