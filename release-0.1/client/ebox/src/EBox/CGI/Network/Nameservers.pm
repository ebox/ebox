package EBox::CGI::Network::Nameservers;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "Network/Index";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $net = EBox::Global->modInstance('network');

	my $dns1 = $self->param("dnsone");
	my $dns2 = $self->param("dnstwo");
	my $dns3 = $self->param("dnsthree");

	$dns1 =~ s/^\s+|\s+$//g;
	$dns2 =~ s/^\s+|\s+$//g;
	$dns3 =~ s/^\s+|\s+$//g;

	$net->setNameservers($dns1, $dns2, $dns3);
}

1;
