=head1 NAME

EBox::LDAP - EBOX LDAP handling module

=head1 DESCRIPTION

This module is used to handle LDAP users, groups and authenthication.

Information about LDAP schemas can be found at:

=over 2

=item person
/etc/ldap/schemas/core.schema

=item posixAccount, shadowAccount
/etc/ldap/schemas/nis.schema

=back

=cut


package EBox::Ldap;


use strict;
use warnings;

use Net::LDAP;
use Net::LDAP::Constant;
use Net::LDAP::Message;
use Net::LDAP::Search;
use Net::LDAP::LDIF;
use Net::LDAP qw(LDAP_SUCCESS);

use EBox::Exceptions::DataExists;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::Internal;
use EBox::Gettext;
use Data::Dumper;


# FIXME To throw exceptions only is needed
#  But for testing purposes, an qw(:try) is added to allow using try catch
use Error qw(:try);

use constant DN => "dc=foo,dc=org";
use constant LDAPI => "127.0.0.1";
=head1 METHODS

=cut


sub new {
	my $class = shift;
	my $self = {};

	# Auth DN where users hang
	$self->{authdn} = 'ou=People,' . DN; 
	
	# Users and groups DNs
	$self->{usersdn} = 'ou=People,' . DN;
	$self->{groupsdn} = 'ou=Group,' . DN;
	
	# Root DN and password
	use constant ROOTDN => 'cn=admin,' . DN;
	use constant ROOTPW => 'foobar';

	# LDAP bind
	#$self->{ldap} = Net::LDAP->new ("ldapi://%2fvar%2frun%2fldapi") or
	$self->{ldap} = Net::LDAP->new (LDAPI)
			or throw EBox::Exceptions::Internal( "Can't create ldapi connection");
	$self->{ldap}->bind(ROOTDN, password=>ROOTPW);

	# FIXME, unbind must be done when object is destroyed
	# FIXME: maybe we can look for other binds before make another one, closing them

	bless($self, $class);
	return $self;
}


sub errorOnLDAP(@){
	my $result = shift;
	my $mesg;
	$mesg = "LDAP operation failed with code " . $result->{resultCode} .
		" and message " . $result->{errorMessage} . "\n";
	print STDERR $mesg; #DEBUG
	print Dumper($result); #DEBUG
	return $result->{resultCode};
}

=head2 auth (user,password)

Function used to authenthicate against EBOX LDAP server

=head3 Returns boolean

True if auth succeeds, False otherwise

=head3 Params

user: string containing user name

password: string containing clear text user password

=head3 Raises no exception

=cut
sub auth ($$$) {
	# FIXME: to be deceased, authenthication will be made via a conf file
	my $self = shift;
	my $ldap = Net::LDAP->new ("ldapi://%2fvar%2frun%2fldapi") or
		throw EBox::Exceptions::Internal("$@");
	my $bind = $ldap->bind ( "cn=$_[1],$self->{authdn}",           
                             password => "$_[2]",
                             version => 3 );          # use for changes/edits
	$ldap->unbind;
	return not $bind->is_error();
}


# TODO: Redefining LDAP schemas can move gid and uid checks to ldap library

sub gidExists($$) {
	my $self = shift;

	my $gid = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => "&(objectclass=*)(gidNumber=$gid)",
		scope => 'one');

	return $result->count > 0;
}

sub groupExists($$) {
	my $self = shift;

	my $group = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => "&(objectclass=*)(cn=$group)",
		scope => 'one');

	return $result->count > 0;
}

sub uidExists($$) {
	my $self = shift;

	my $uid = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(uidNumber=$uid)",
		scope => 'one');

	return $result->count > 0;
}

sub userExists($$) {
	my $self = shift;

	my $user = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(cn=$user)",
		scope => 'one');

	return $result->count > 0;
}

sub getGroupGid($$) {

	my $self = shift;

	my $groupname = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => "&(objectclass=*)(cn=$groupname)",
		scope => 'one',
		attr => ['gidNumber']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getGroupGid: " . 
			$result->error);
	}

	# If search result is null group doesnt exists
	if ($result->count == 0) {
		throw EBox::Exceptions::DataNotFound(
			'data' => "Group", 'value' => $groupname);
	}

	return $result->entry(0)->get_value('gidNumber');

}


sub getGidGroup($$) {
	my $self = shift;

	my $gid = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => "&(objectclass=*)(gidNumber=$gid)",
		scope => 'one',
		attr => ['cn']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getGidGroup: " . 
			$result->error);
	}

	# If search result is null group doesnt exists
	if ($result->count == 0) {
		throw EBox::Exceptions::DataNotFound(
			'data' => "Gid", 'value' => $gid);
	}

	return $result->entry(0)->get_value('cn');

}


sub groupHaveUsers($$) {
	my $self = shift;

	my $gid = shift;


	my $ldap = $self->{ldap};
	
	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(gidNumber=$gid)",
		scope => 'one');

	return $result->count > 0;
}


sub getGroupUsers ($$) {
	my $self = shift;

	my $groupname = shift;

	my $ldap = $self->{ldap};

	my $gid = $self->getGroupGid($groupname);

	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => "&(objectclass=*)(gidNumber=$gid)",
		scope => 'one',
		attrs => ['memberUid']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getGroupUsers: " . 
			$result->error);
	}

	# Construct return array
	my @users= ();
	foreach ($result->sorted('memberUid'))
	{
		@users = (@users, $_->get_value('memberUid'));
	}

	return @users;

}


sub getUserGroup ($$) {
	my $self = shift;

	my $username = shift;

	my $ldap = $self->{ldap};

	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(uid=$username)",
		scope => 'one',
		attrs => ['gidNumber']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getUserGroup: " . 
			$result->error);
	}

	my $gid = $result->entry(0)->get_value('gidNumber');

	return $self->getGidGroup($gid);

}


sub isLastUser($$) {
	my $self = shift;

	my $username = shift;

	my $ldap = $self->{ldap};

	# Find user group gid
	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(uid=$username)",
		scope => 'one',
		attrs => ['gidNumber']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::isLastUser: " . 
			$result->error);
	}

	my $gid = $result->entry(0)->get_value('gidNumber');


	# Find users with this gid
	$result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(gidNumber=$gid)",
		scope => 'one');


	return $result->count == 1;
}


=head2 addGroup (group)

=head3 Returns nothing

=head3 Params

group is a hash reference containing:

=over 3

=item name
LDAP cn

=item gid
LDAP gidNumber

=item desc
LDAP description

=back

=head3 Raises

FIXME raised exceptions

=cut
sub addGroup ($$$) {
	my $self = shift;

	my $group = shift;
	my $comment = shift;
	#FIXME
	my $gid = $self->getLastGid + 1;
	
	# Verify GID
	if ($self->gidExists($gid)){
		throw EBox::Exceptions::DataExists('data' => 'gid',
                                                  'value' => $gid);
	}


	my $ldap = $self->{ldap};

	my $result = $ldap->add(
		"cn=" . $group ."," . $self->{groupsdn},
		attr => [
			'cn' => $group,
			'gidNumber' => $gid,
			'description' => $comment,
			'objectclass' => ['posixGroup']
		]);


	# Error handling
	if ($result->is_error) {
		# Group to be added already exists
		if ($result->error_name eq 'LDAP_ALREADY_EXISTS') {
			throw EBox::Exceptions::DataExists('data' => 'group',
							  'value' => $group);
		} else {
			throw EBox::Exceptions::Internal(
				"Unknown error at Ebox::LDAP::addGroup: " . 
				$result->error);
		}
	}

}


=head2 delGroup (group)

=head3 Returns nothing

=head3 Params

group: string containing group name

=head3 Raises

FIXME raised exceptions

=cut
sub delGroup($$) {
	my $self = shift;

	my $group = shift;	

	my $ldap = $self->{ldap};

	my $result = $ldap->delete("cn=" . $group . "," . $self->{groupsdn});

	# Error handling
	if ($result->is_error) {
		# Group to be deleted doesn't exists
		if ($result->error_name eq 'LDAP_NO_SUCH_OBJECT') {
			throw EBox::Exceptions::DataNotFound(
				'data' => "Group", 'value' => $_[0]);
		} else {
			throw EBox::Exceptions::Internal(
				"Unknown error at Ebox::LDAP::delGroup: " . 
				$result->error);
		}
	}

}

sub delUserFromGroup($$$) {
	my $self = shift;

	my $user = shift;
	my $group = shift;

	my $ldap = $self->{ldap};

	my $dn = "cn=" . $group . "," . $self->{groupsdn};
  
  	my $result = $ldap->modify("$dn", delete => { memberUid => "$user"} );
	
	# Error handling
	if ($result->is_error) {
		# Group to be deleted doesn't exists
		# FIXME Report if user does not exist
		if ($result->error_name eq 'LDAP_NO_SUCH_OBJECT') {
			throw EBox::Exceptions::DataNotFound(
				'data' => "Group", 'value' => $group);
		} else {
			throw EBox::Exceptions::Internal(
				"Unknown error at Ebox::LDAP::delGroup: " . 
				$result->error);
		}
	}

}

sub addUserToGroup($$$) {
	my $self = shift;

	my $user = shift;
	my $group = shift;

	my $ldap = $self->{ldap};

	my $dn = "cn=" . $group . "," . $self->{groupsdn};
  
  	my $result = $ldap->modify("$dn", add => { memberUid => "$user"} );
	
	# Error handling
	if ($result->is_error) {
		# Group to be deleted doesn't exists
		# FIXME Report if user does not exist
		if ($result->error_name eq 'LDAP_NO_SUCH_OBJECT') {
			throw EBox::Exceptions::DataNotFound(
				'data' => "Group", 'value' => $group);
		} else {
			throw EBox::Exceptions::Internal(
				"Unknown error at Ebox::LDAP::delGroup: " . 
				$result->error);
		}
	}

}
=head2 modifyGroup (group,newAttrs)

=head3 Returns nothing

=head3 Params

group is a string containing group name before changes

newAttrs is a hash reference containing:

=over 3

=item name
LDAP cn

=item gid
LDAP gidNumber

=item desc
LDAP description

=back

=head3 Raises

FIXME raised exceptions

=cut
sub modifyGroup ($$$) {
	my $self = shift;

	my $name = shift;
	my $group = shift;

	my $ldap = $self->{ldap};

	# TODO Check group name doesn't exists
	# TODO Check for null args

	if ($name eq $group->{'name'}) {
	
		my $result = $ldap->modify(
			"cn=" . $name . "," . $self->{groupsdn},
			replace => {
				'gidNumber' => $group->{'gid'},
				'description' => $group->{'desc'}
			});


		# Error handling
		if ($result->is_error) {
			# Group to be added already exists
			if ($result->error_name eq 'LDAP_ALREADY_EXISTS') {
			throw EBox::Exceptions::DataExists('data' => 'group',
							  'value' => $_[0]);
			} else {
				throw EBox::Exceptions::Internal(
				  "Unknown error at Ebox::LDAP::modifyGroup: ".
				  $result->error_name);
			}
		}

	} else {

		# We can't change DN of the entry we are modifying,
		# so we delete and add
		# FIXME: fix null args using old values
		$self->delGroup($name);

		$self->addGroup($group);
	
	}
	
}


=head2 addUser (user)

=head3 Returns nothing

=head3 Params

User is a hash containing:

=over 6

=item account
LDAP uid 

=item name
LDAP cn

=item surname
LDAP sn

=item uid 
LDAP uidNumber

=item gid
LDAP gidNumber

=item desc
LDAP description

=back

To call it, a reference to a hash must be passed: addUser(\%user)

=head3 Raises

FIXME

=cut
sub addUser ($$$$$) {
	my $self = shift;

	my $user = shift;
	my $password = shift;
	my $group = shift;
	my $comment = shift;


	# Verify user don't exists
	if ($self->userExists($user)) {
		throw EBox::Exceptions::DataExists('data' => __('user name'),
                                                   'value' => $user);
	}

	# Verify group exists
	unless ($self->groupExists($group)) {
		throw EBox::Exceptions::DataNotFound('data' => __('group name'),
                                                     'value' => $group);
	}

	my $ldap = $self->{ldap};

	my $uid = $self->getLastUid + 1;
	my $gid = $self->getGroupGid($group);


#	my $result = $ldap->add(
#		"uid=" . $user . "," . $self->{usersdn},
#		attr => [
#			'uid' => $user,
#			'userPassword' => $password,
#			'cn' => $user,
#			'homeDirectory' => "/home/foo",
#			'uidNumber' => 2500,
#			'gidNumber' => $gid,
#			'description' => $comment,
#			'objectclass' => [ 'person', 'posixAccount', 'shadowAccount']
#		]);
	my $result = $ldap->add(
		"cn=" . $user . "," . $self->{usersdn},
		attr => [
			'cn' => $user,
			'sn' => $user,
			'uid' => $user,
			'uidNumber' => $uid,
			'gidNumber' => $gid,
			'homeDirectory' => "/home/foo",		
			'userPassword' => $password,
			'description' => $comment,
			'objectclass' => [ 'inetOrgPerson', 'posixAccount']
		]);

	# Error handling
	if ($result->is_error) {
		# Value with invalid syntax
		if ($result->error_name eq 'LDAP_INVALID_SYNTAX') {
			if ($result->error eq 'uidnumber: value #0 invalid per syntax') {
				throw EBox::Exceptions::InvalidData('data' => 'uidNumber',
							            'value' => $user);
			} elsif ($result->error eq 'gidnumber: value #0 invalid per syntax') {
				throw EBox::Exceptions::InvalidData('data' => 'gidNumber',
				                                    'value' => $group);
			} else {
				throw EBox::Exceptions::Internal(
			 	  "Unknown error at Ebox::LDAP::addUser: " . 
				  $result->error);
			}

		} else {
			throw EBox::Exceptions::Internal(
				"Unknown error at Ebox::LDAP::addUser: " . 
				$result->error);
		}
	}

}


=head2 delUser (user)

=head3 Returns nothing

=head3 Params

user: string containing user name

=head3 Raises

FIXME raised exceptions

=cut
sub delUser($$) {
	my $self = shift;

	my $user = shift;	

	my $ldap = $self->{ldap};

	my $result = $ldap->delete("uid=" . $user . "," . $self->{usersdn});
	
	print $result;
	# Error handling
	if ($result->is_error) {
		# User to be deleted doesn't exists
		if ($result->error_name eq 'LDAP_NO_SUCH_OBJECT') {
			throw EBox::Exceptions::DataNotFound(
				'data' => "user", 'value' => $user);
		} else {
			throw EBox::Exceptions::Internal(
				"Unknown error at Ebox::LDAP::delUser: " . 
				$result->error);
		}
	}

}


=head2 getGroups() 

Get group list

=head3 Params none

=head3 Returns group list

An array of hashes consisting of:

account: LDAP cn used as group account

gid: LDAP gidNumber

desc: description of the group

=head3 Raises

FIXME raised exceptions

=cut
sub getGroups ($) {

	my $self = shift;

	my $ldap = $self->{ldap}; 

	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => '(objectclass=*)',
		scope => 'one', attrs => ['cn', 'gidNumber', 'description']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getGroups: " . 
			$result->error);
	}

	# Construct return array
	my @groups = ();
	foreach ($result->sorted('cn'))
	{
		@groups = (@groups, {
			'account' => $_->get_value('cn'),
			'gid' => $_->get_value('gidNumber'),
			'desc' => $_->get_value('description')});
	}

	return @groups;
}

sub getLastGid($) {
	my $self = shift;

	my $ldap = $self->{ldap}; 

	my $result = $ldap->search(
		base => $self->{groupsdn},
		filter => '(objectclass=posixAccount)',
		scope => 'one', attrs => ['gidNumber']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getGroups: " . 
			$result->error);
	}

	# Construct return array
	my @groups = $result->sorted('gidNumber');

	my $gid = -1;
	foreach my $group (@groups) {
		my $currgid = $group->get_value('gidNumber');
		if ( $currgid > $gid){
			$gid = $currgid;
		}
	}
	
	return $gid;
}

=head2 getUsers() 

Get user list

=head3 Params none

=head3 Returns user list

An array of hashes consisting of:

account: LDAP uid used as user account

name: LDAP cn used as user name

surname: LDAP sn used as user surname

uid: LDAP uidNumber

group: LDAP gidNumber

desc: description of the user

=head3 Raises

FIXME raised exceptions

=cut
sub getUsers ($) {

	my $self = shift;

	my $ldap = $self->{ldap};

	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => '(objectclass=*)',
		scope => 'one',
		attrs => ['uid', 'cn', 'sn', 'homeDirectory', 'uidNumber', 'gidNumber', 'description']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getUsers: " . 
			$result->error);
	}

	# Construct return array
	my @users = ();
	foreach ($result->sorted('uid'))
	{
		@users = (@users, {
			account => $_->get_value('uid'),
			name => $_->get_value('cn'),
			surname => $_->get_value('sn'),
			homeDirectory => $_->get_value('homeDirectory'),
			uid => $_->get_value('uidNumber'),
			group => $_->get_value('gidNumber'),
			desc => $_->get_value('description')});
	}

	return @users;

}

sub getUserInfo($$) {
	my $self = shift;
	my $user = shift;
	
	# Verify user don't exists
	unless ($self->userExists($user)) {
		throw EBox::Exceptions::DataExists('data' => __('user name'),
                                                   'value' => $user);
	}
	
	my $ldap = $self->{ldap};

	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => "&(objectclass=*)(cn=$user)",
		scope => 'one',
		attrs => ['cn','description']);
	
	# Error handling
	if ($result->is_error or $result->count != 1) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getUsers: " . 
			$result->error);
	}

	my $userinfo = { 
			username => $result->entry(0)->get_value('cn'), 
			comment  => $result->entry(0)->get_value('description') 
			};

	return $userinfo;
}

sub getLastUid($) {
	my $self = shift;

	my $ldap = $self->{ldap}; 

	my $result = $ldap->search(
		base => $self->{usersdn},
		filter => '(objectclass=posixAccount)',
		scope => 'one', attrs => ['uidNumber']);

	# Error handling
	if ($result->is_error) {
		throw EBox::Exceptions::Internal(
			"Unknown error at Ebox::LDAP::getLastUid: " . 
			$result->error);
	}

	# Construct return array
	my @users = $result->sorted('uidNumber');

	my $uid = -1;
	foreach my $user (@users) {
		my $curruid = $user->get_value('uidNumber');
		if ( $curruid > $uid){
			$uid = $curruid;
		}
	}
	
	return $uid;
}








###########################################

# WORK IN PROGRESS
#
# Subroutines to read LDAP entries from text files

###########################################


#			$self->{authdn} = 'dc=ebox';
#			$passwd = $self->{rootpw};
#			$userToAuthenticate = 'admin';


my @ldif_files = ('./calamario.ldif', './cefalopodos.ldif');






=head2 ldif_entries_ok (filename)

=head3 Returns boolean

True if ldif entries in file are ok

False otherwise

=head3 Params

filename

=head3 Raises no exception

=cut
sub ldif_entries_ok ($$) {

	my $self = shift;

	my $ldif_file = shift; 

	my $ldap = $self->{ldap};

	my $schema = $ldap->schema();
	my $ldif = Net::LDAP::LDIF->new( $ldif_file, "r", onerror => 'undef' );

	print "Verifying LDIF entries of $ldif_file\n";
	my $ldf_err;

	while( not $ldif->eof() ) {

		# Read one entry taking care of errors
		my $entry = $ldif->read_entry();
		if ( $ldif->error() ) {
			print "\nError msg: ",$ldif->error(),"\n";
			print "\nError lines:\n",$ldif->error_lines(),"\n";
			$ldf_err++;
			# Exit loop
			last;
		}
		
		# Integrity check
		my $schemaobj;
		$schemaobj = $ldap->search(
			base => $entry->dn, filter => '(objectclass=*)',
			scope => 'base', attrs => ['cn']);
		if ($entry->changetype eq 'add' and $schemaobj->entries > 0) {
			print "Add entry already exists:\n  ",$entry->dn,"\n";
			$ldf_err++;
		}
		elsif ( ($entry->changetype eq 'delete' or $entry->changetype eq 'modify')
			and $schemaobj->entries == 0) {
			print "Modify or Delete entry does not exist:\n  ", $entry->dn,"\n";
			$ldf_err++;
		}
		else {
			print "Entry Ok: ", $entry->dn,"\n";
		}

	}

	$ldif->done();

	if ($ldf_err) {
		print "\nAborting, errors found\n";
		return 0;
	} else {
		print "\nVerification complete\n";
		return 1;
	}

}


=head2 read_ldif_entries (filename)

PRE: filename LDIF is ok

=head3 Returns nothing

=head3 Params

filename

=head3 Raises no exception

=cut
sub read_ldif_entries ($$) {

	my $self = shift;

	my $ldif_file = shift;

	my $ldap = $self->{ldap};

	my $ldif = Net::LDAP::LDIF->new( $ldif_file, "r", onerror => 'undef' );

	print "Importing LDIF entries of $ldif_file";

	while( not $ldif->eof() ) {

		my $entry = $ldif->read_entry();

		if ( $ldif->error() ) {
			print "\nError msg: ",$ldif->error(),"\n";
			print "\nError lines:\n",$ldif->error_lines(),"\n";
			last;
		} else {
			print ".";
			my $res = $entry->update( $ldap );
			if ($res->code) {
				print "\nError inserting entry: ", $res->error,"\n";
				last;
			}
		}
	}
	print "done\n";
	$ldif->done();
}


=head2 void import_ldif_entries (filenames)

Runs read_ldif_entries if ldif entries are ok for each filename argument

=head3 Returns nothing

=head3 Params

filenames

=head3 Raises no exception

=cut
sub import_ldif_entries ($@) {

	my $self = shift;

	foreach (@_) {
		if ($self->ldif_entries_ok($_)) {
			$self->read_ldif_entries ($_)
		};
	}
}


1;

=head1 AUTHORS

This module was written by

=over 1

=item Héctor Blanco Alcaine <hector@warp.es>

=back

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

http://www.gnu.org/copyleft/gpl.html

=cut
