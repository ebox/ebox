package EBox::CGI::UsersAndGroups::DelGroup;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Exceptions::DataExists;
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
	$self->_requireParam('groupname', __('group name'));

	if (defined($self->param("deletewithusers"))) {
		$usersandgroups->delGroupWithUsers($self->param("groupname"));
		return;
	}  elsif (defined($self->param("cancel"))) {
		return;
	}

	try {
		$usersandgroups->delGroup($self->param('groupname'));
	} catch EBox::Exceptions::DataExists with {
		$self->{template} = '/usersandgroups/delete_group.tmpl';
		$self->{redirect} = undef;
		my @array = ();
		push(@array, {'groupname' => $self->param("groupname")});
		$self->{params} = \@array;
	};
}


1;
