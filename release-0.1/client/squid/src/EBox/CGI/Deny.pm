package EBox::CGI::Squid::Deny;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Squid',
				      @_);
	$self->{redirect} = "Squid/Index";
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $squid = EBox::Global->modInstance('squid');
	my @names = $self->cgi->param;
	
	$squid->addExceptions();
	if ( $#names > 0 ){
		pop @names;
		my @exceptions;
		foreach (@names){
			my @dupla = ( $_, "listAllow");
			push (@exceptions, \@dupla);
		}
		$squid->addExceptions(@exceptions);
	}
	$squid->changeGlobalPolicy("deny");
	$squid->setAuth("no");


}

1;
