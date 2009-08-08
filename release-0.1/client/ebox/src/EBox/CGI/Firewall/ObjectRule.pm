package EBox::CGI::Firewall::ObjectRule;

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
	$self->{errorchain} = undef;

	$self->{redirect} = "Firewall/Object?object=". $self->param("object");

	if (defined($self->param('add'))) {
		$self->_requireParam('action', __('action'));
		$self->_requireParam('protocol', __('protocol'));
		$self->_requireParam('port', __('port'));
		$firewall->addObjectRule($self->param("object"),
				      $self->param("action"),
				      $self->param("protocol"),
				      $self->param("port"),
				      $self->param("address"),
				      $self->param("mask"));
	} elsif (defined($self->param('delete'))) {
		$self->_requireParam('rulename', __('rule'));
		$firewall->removeObjectRule($self->param("object"),
					 $self->param("rulename"));
	} elsif (defined($self->param('change'))) {
		my $active = undef;
		if ($self->param("active") eq 'yes') {
			$active = 1;
		}
		$self->_requireParam('rulename', __('rule'));
		$self->_requireParam('action', __('action'));
		$self->_requireParam('protocol', __('protocol'));
		$self->_requireParam('port', __('port'));
		$firewall->changeObjectRule($self->param("object"),
				      $self->param("rulename"),
				      $self->param("action"),
				      $self->param("protocol"),
				      $self->param("port"),
				      $self->param("address"),
				      $self->param("mask"),
				      $active);
	} elsif (defined($self->param('up'))) {
		$self->_requireParam('rulename', __('rule'));
		$firewall->ObjectRuleUp($self->param('object'),
					$self->param('rulename'));
	} elsif (defined($self->param('down'))) {
		$self->_requireParam('rulename', __('rule'));
		$firewall->ObjectRuleDown($self->param('object'),
					$self->param('rulename'));
	}

}

1;
