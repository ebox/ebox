package EBox::CGI::Squid::Allow;

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
			my @dupla = ( $_, "listDeny");
			push (@exceptions, \@dupla);
		}
		$squid->addExceptions(@exceptions);
	}
	$squid->changeGlobalPolicy("allow");
	$squid->setAuth("no");


}

1;
