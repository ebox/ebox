package EBox::CGI::Firewall::Redirection;

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
	$self->{redirect} = "Firewall/Index";
	return $self;
}

sub _process($) {
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');

	if (defined($self->param('add'))) {
		$self->_requireParam('proto', __('protocol'));
		$self->_requireParam('iface', __('network interface'));
		$self->_requireParam('eport', __('external port'));
		$self->_requireParam('address', __('destination address'));
		$self->_requireParam('dport', __('destination port'));
		$firewall->addPortRedirection($self->param("proto"),
					      $self->param("eport"),
					      $self->param("iface"),
					      $self->param("address"),
					      $self->param("dport"));
	} elsif (defined($self->param('delete'))) {
		$self->_requireParam('oldproto', __('protocol'));
		$self->_requireParam('oldeport', __('external port'));
		$self->_requireParam('oldiface', __('network interface'));
		$firewall->removePortRedirection($self->param("oldproto"),
						 $self->param("oldeport"),
						 $self->param("oldiface"));
	} elsif (defined($self->param('change'))) {
		$self->_requireParam('oldproto', __('protocol'));
		$self->_requireParam('oldeport', __('external port'));
		$self->_requireParam('oldiface', __('network interface'));
		$self->_requireParam('iface', __('network interface'));
		$self->_requireParam('proto', __('protocol'));
		$self->_requireParam('eport', __('external port'));
		$self->_requireParam('address', __('destination address'));
		$self->_requireParam('dport', __('destination port'));
		$firewall->removePortRedirection($self->param("oldproto"),
						 $self->param("oldeport"),
						 $self->param("oldiface"));

		$firewall->addPortRedirection($self->param("proto"),
					      $self->param("eport"),
					      $self->param("iface"),
					      $self->param("address"),
					      $self->param("dport"));
	}

}

1;
