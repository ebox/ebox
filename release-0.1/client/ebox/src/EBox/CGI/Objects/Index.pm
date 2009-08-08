package EBox::CGI::Objects::Index;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Objects;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Objects',
				      'template' => '/objects/index.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $objects = EBox::Global->modInstance('objects');

	my @array = ();

	my $objarray = $objects->getObjectsArray;

	defined($objarray) and
		push(@array, {'objects' => $objects->getObjectsArray});

	if (defined $self->param("show")) {
		push(@array, {'show' => $self->param('show')});
	} else {
		push(@array, {'show' => ""});
	}

	$self->{params} = \@array;
}

1;
