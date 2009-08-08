package EBox::CGI::Squid::Transparent;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'squid',
				      @_);
	$self->{redirect} = "Squid/Index";	
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $squid = EBox::Global->modInstance('squid');
	$self->_requireParam('active', __('Transparent Proxy Status'));
	$squid->setTransproxy($self->param("active"));
	
	
}

1;
