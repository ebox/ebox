package EBox::CGI::UsersAndGroups::ModGroup;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;

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

	my $users = EBox::Global->modInstance('usersandgroups');
	$self->_requireParam('groupname', __('group name'));
	$self->_requireParam('name', __('old group name'));
	$self->_requireParam('gid', __('group id'));
	$self->_requireParam('desc', __('group description'));

	$users->modifyGroup($self->param('groupname'),
				{ name => $self->param('oldgroupname'),
				  gid => $self->param('oldgid'),
				  desc => $self->param('oldgroupdescription')}
			);
}

1;
