package EBox::CGI::Finish;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Save configuration',
				      'template' => '/finish.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;

	my $global = EBox::Global->modInstance('global');

	if (defined($self->param('save'))) {
		$global->saveAllModules;
		$self->{redirect} = "/Summary/Index";
	} elsif (defined($self->param('cancel'))) {
		$global->revokeAllModules;
		$self->{redirect} = "/Summary/Index";
	} else {
		if ($global->unsaved) {
			my @array = ();
			push(@array, {'unsaved' => 'yes'});
			$self->{params} = \@array;
		}
	}
}

1;
