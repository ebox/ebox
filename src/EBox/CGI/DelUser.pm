package EBox::CGI::UsersAndGroups::DelUser;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

use EBox::Exceptions::DataMissing;
use Error qw(:try);

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";



sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{redirect} = "UsersAndGroups/Index";
	bless($self, $class);
	return $self;
}


sub _process($) {
	my $self = shift;
	
	my $usersandgroups = EBox::Global->modInstance('usersandgroups');
	$self->_requireParam('useraccount', __('user name'));

	if (defined($self->param("deletewithgroup"))) {
		$usersandgroups->delUserWithGroup($self->param("useraccount"));
		return;	
	}  elsif (defined($self->param("deleteforce"))) {
		$usersandgroups->delUserForce($self->param("useraccount"));
		return;
	}

	try {
		$usersandgroups->delUser($self->param('useraccount'));
	} catch EBox::Exceptions::DataMissing with {
		$self->{template} = '/usersandgroups/delete_user.tmpl';
		$self->{redirect} = undef;
		my @array = ();
		push(@array, {'useraccount' => $self->param("useraccount")});
		$self->{params} = \@array;
	};

}


1;
