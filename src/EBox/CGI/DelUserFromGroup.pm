package EBox::CGI::UsersAndGroups::DelUserFromGroup;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::UsersAndGroups;
use EBox::Gettext;


sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Users and Groups',
				      @_);
#        $self->{redirect} = "UsersAndGroups/Group";
	bless($self, $class);
	return $self;
}


sub _process($) {
	my $self = shift;
	my $usersandgroups = EBox::Global->modInstance('users');

	my @args = ();

	$self->_requireParam('deluser', __('user'));
	$self->_requireParam('group' , __('group'));
	
	my @users = $self->param('deluser');
	my $group = $self->param('group');
	
	foreach my $us (@users){
		$usersandgroups->delUserFromGroup($us, $group);
	}

	# FIXME Is there a better way to pass parameters to redirect/chain
        # cgi's
        $self->{redirect} = "UsersAndGroups/Group?group=$group";

}


1;
