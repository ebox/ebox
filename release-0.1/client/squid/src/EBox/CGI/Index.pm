package EBox::CGI::Squid::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use Storable qw(dclone);

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title'    => 'Squid',
				      'template' => 'squid/objects-modify.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $squid = EBox::Global->modInstance('squid');
	my $objectobj = EBox::Global->modInstance('objects');
	my @names = $self->cgi->param;
	my @objects;
	
	if ( defined $objectobj->getObjectsArray()){
		 @objects = @{dclone($objectobj->getObjectsArray())}; 
	}else{
		@objects = ();
	}
	foreach ( @objects ){
		 $_->{'checked'} = $squid->isExcep($_->{'name'}) 
		 		                  ? "checked " : " " ;
	}
		
	my @array = ();
	push (@array, {'object'    	=> '1'});
	push (@array, {'policy' 	=> ucfirst $squid->getGlobalPolicy});
	push (@array, {'global' 	=> $squid->getGlobalPolicy
						  eq "allow" ? " ": ""});
	push (@array, { 'active'	=> $squid->getService() 
						  eq "yes" ? " ": ""});
	push (@array, {'transparent' 	=> $squid->getTransproxy()
						  eq "yes" ? " ": "" });
	push (@array, {'port'  		=> $squid->getPort});
	push (@array, {'objects' 	 	=> \@objects} );
	$self->{params} = \@array;
	

}

1;
