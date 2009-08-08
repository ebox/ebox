# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package EBox::LdapUserBase;

use strict;
use warnings;

use EBox::Gettext;

sub new
{
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

# When a new user is created this method is called
sub _addUser($$)
{

}

# When a user is deleted this method is called
sub _delUser($$)
{

}

# When a user is modified this method is called
sub _modifyUser($$)
{

}

# When a user is to be deleted, modules should warn the sort of  data
# (if any) is going to be removed
sub _delUserWarning($$)
{

}

# When a new group is created this method is called
sub _addGroup($$)
{

}

# When a group is deleted this method is called
sub _delGroup($$)
{

}

# When a group is to be deleted, modules should warn the sort of  data
# (if any) is going to be removed
sub _delGroupWarning($$)
{

}

# When a user is to be edited, this method is called to get customized
# mason components from modules depending on users stored in LDAP.
# Thus, these components will be showed below the basic user data
# The method has to return a hash ref containing:
# 	'path'   => MASON_COMPONENT_PATH_TO_BE_ADDED
# 	'params' => PARAMETERS_FOR_MASON_COMPONENT
sub _userAddOns($$)
{

}

# When a group is to be edited, this method is called to get customized
# mason components from modules depending on groups stored in LDAP.
# Thus, thesecomponents will be showed below the basic group data
# The method has to return a hash ref containing:
# 	'path'   => MASON_COMPONENT_PATH_TO_BE_ADDED
# 	'params' => PARAMETERS_FOR_MASON_COMPONENT
sub _groupAddOns($$)
{

}

# Those modules which need to use their own LDAP schemas must implement 
# this method. It must return an array with LDAP schemas.
sub _includeLDAPSchemas
{
	return [];	
}

# Those modules which need to include their own acls for the LDAP
# configuration must implement this method. It must return an array
# containing acl's
sub _includeLDAPAcls
{
	return [];
}
1;
