package EBox::CGI::General;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use POSIX qw(setlocale LC_ALL);

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'General configuration',
				      'template' => '/general.tmpl',
				      @_);
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;

	my $global = EBox::Global->modInstance('global');

	if (defined($self->param('password'))) {
		$self->_requireParam("currentpwd", "Password");
		my $curpwd = $self->param('currentpwd');
		my $newpwd1 = $self->param('newpwd1');
		my $newpwd2 = $self->param('newpwd2');
		defined($newpwd1) or $newpwd1 = "";
		defined($newpwd2) or $newpwd2 = "";

		unless (EBox::Auth->checkPassword($curpwd)) {
			$self->{error} = __('Incorrect password.');
			return;
		}

		unless ($newpwd1 eq $newpwd2) {
			$self->{error} = __('New passwords do not match.');
			return;
		}
		unless (length($newpwd1) > 5) {
			$self->{error} = __('The password must be at least 6 '.
					    'characters long');
			return;
		}
		EBox::Auth->setPassword($newpwd1);
		$self->{msg} = __('The password was changed successfully.');
	} elsif (defined($self->param('lang'))) {
		$global->setLocale($self->param('lang'));
		POSIX::setlocale(LC_ALL,$global->locale());
	}
}

1;
