# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
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

package EBox::MailAliasLdap;

use strict;
use warnings;

use EBox::Sudo qw( :all );
use EBox::Global;
use EBox::Ldap;
use EBox::MailUserLdap;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;
use EBox::Gettext;
use EBox::Validate;
use EBox::MailVDomainsLdap;

use constant ALIASDN     => 'ou=mailalias, ou=postfix';

sub new 
{
	my $class = shift;
	my $self  = {};
	$self->{ldap} = EBox::Ldap->instance();
	bless($self, $class);
	return $self;
}

# Method: addAlias
#
#  Creates a new mail alias to an account.
#
# Parameters:
#
#     alias - The mail alias account to create
#		maildrop - The mail account(s) to send all mail
#		id - the username or groupname
sub addAlias ($$$$) { 
	my $self = shift;
	my $alias = shift;
	my $maildrop = shift;
	my $id = shift;
	
#	RFC compliant
	unless ($alias =~ /^[^\.\-][\w\.\-]+\@[^\.\-][\w\.\-]+$/) {
		throw EBox::Exceptions::InvalidData('data' => __('mail account'),
														'value' => $alias);
   }
	# Verify mail exists
	if ($self->accountExists($alias)) {
		throw EBox::Exceptions::DataExists('data' => __('mail account'),
														'value' => $alias);
	}

        $self->_addCouriermailAliasLdapElement($id, $alias, $maildrop);
}

# Method: addGroupAlias
#
#  Creates a new mail alias to a group of users
#
# Parameters:
#
#     alias - The mail alias account to create
#		groupname - The group name.
sub addGroupAlias ($$$) { #mail alias, groupname
	my $self = shift;
	my $alias = shift;
	my $groupname = shift;
	my $users = EBox::Global->modInstance('users');

	unless ($alias =~ /^[^\.\-][\w\.\-]+\@[^\.\-][\w\.\-]+$/) {
		throw EBox::Exceptions::InvalidData('data' => __('mail account'),
														'value' => $alias);
   }
	
	if ($self->accountExists($alias)) {
		throw EBox::Exceptions::DataExists('data' => __('mail account'),
														'value' => $alias);
	}

	my $mailUserLdap = EBox::MailUserLdap->new();

	my @mailAccounts = map {
	    $mailUserLdap->userAccount($_)
	} $mailUserLdap->usersWithMailInGroup($groupname);


	my $aux = 0;
	foreach my $mail (@mailAccounts)
	{
		if ($aux++ == 0) { 
			$self->addAlias($alias, $mail, $groupname); 
		} else {
			$self->addMaildrop($alias, $mail);
		}
	}

}


# Method: addVDomainALias
#
#  Creates a new domain alias  for a mail domain
#
# Parameters:
#
#     vdomain - The mail domain for aliasing
#     alias   - The mail alias domain  to create
sub addVDomainAlias
{
    my ($self, $vdomain, $alias) = @_;
    

    EBox::Validate::checkDomainName($alias, __('Domain alias'));

    my $vdomainsLdap =  EBox::MailVDomainsLdap->new();
    if (not $vdomainsLdap->vdomainExists($vdomain)) {
        throw EBox::Exceptions::External(__x(
                                             'Mail domain {d} does not exists',
                                             d => $vdomain
                                            )
                                        );
    }
    if ($vdomainsLdap->vdomainExists($alias)) {
                throw EBox::Exceptions::External(__x(
  'Cannot use {d} as alias for a mail domain because a domain which this name already exists',
                                             d => $vdomain
                                            )
                                        );
    }


    if ($self->aliasExists($alias)) {
        throw EBox::Exceptions::DataExists(data => __('Domain alias'));
    }

    my $id = 0;
    $alias = '@' . $alias;
    $vdomain = '@' . $vdomain;
    $self->_addCouriermailAliasLdapElement($id, $alias, $vdomain);
}



# Method: vdomainAliases
#
#  return all the domain alias for a domain. 
#
# Parameters:
#
#     vdomain - The mail domain 
sub vdomainAliases
{
    my ($self, $vdomain) = @_;

    my $vdomainsLdap =  EBox::MailVDomainsLdap->new();
    if (not $vdomainsLdap->vdomainExists($vdomain)) {
        throw EBox::Exceptions::External(__x(
                                             'Mail domain {d} does not exists',
                                             d => $vdomain
                                            )
                                        );
    }

    my %attrs = (
            base => $self->aliasDn,
            filter => "&(objectclass=couriermailalias)(maildrop=@".$vdomain.")",
            scope => 'sub'
                );

    my $result = $self->{'ldap'}->search(\%attrs);

    my @alias = map { $_->get_value('mail')} $result->sorted('mail');

    return \@alias;
}






sub _addCouriermailAliasLdapElement
{
    my ($self, $id, $alias, $maildrop) = @_;

    my $dn = "mail=$alias, " . $self->aliasDn();
    my %attrs = ( 
                 attr => [
                          'objectclass'           => 'couriermailalias',
                          'objectclass'           =>      'account',
                          'userid'                => $id,
                          'mail'                  => $alias,
                          'maildrop'              => $maildrop
                         ]
                );
    
    my $r = $self->{'ldap'}->add($dn, \%attrs);

}

# Method: updateGroupAlias
#
#  When a change on users of a group this method updates the maildrops of the
#  mail alias account.
#
# Parameters:
#
#		group - The group name
#     alias - The mail alias account to create
sub updateGroupAlias ($$$) {
	my ($self, $group, $alias) = @_;

	my $users = EBox::Global->modInstance('users');

	unless ($self->accountExists($alias)) {
		throw EBox::Exceptions::DataNotFound('data' => __('mail account'),
														'value' => $alias);
	}

	$self->delAliasGroup($group);
	$self->addGroupAlias($alias,$group);
}

# Method: addMaildrop
#
#	This method adds a new maildrop to an existing mail alias account (used on
#	group mail alias accounts).
#
# Parameters:
#
#     alias - The mail alias account to create
#		maildrop - The mail account to add to the alias account
sub addMaildrop ($$$) { #alias account, mail account to add
	my $self = shift;
	my $alias = shift;
	my $maildrop = shift;

	unless ($self->aliasExists($alias)) {
		throw EBox::Exceptions::DataNotFound('data' => __('mail alias account'),
														'value' => $alias);
	}

	my $dn = "mail=$alias, " . $self->aliasDn();

	my %attrs = (
		changes => [
			add => [ 'maildrop'	=> $maildrop ]
		]
	);

	my $r = $self->{'ldap'}->modify($dn, \%attrs);
}

# Method: delMaildrop
#
#	This method removes a maildrop to an existing mail alias account (used on
#	group mail alias accounts).
#
# Parameters:
#
#     alias - The mail alias account to create
#		maildrop - The mail account to add to the alias account
sub delMaildrop ($$$) { #alias account, mail account to remove
	my $self = shift;
	my $alias = shift;
	my $maildrop = shift;

	unless ($self->aliasExists($alias)) {
		throw EBox::Exceptions::DataNotFound('data' => __('mail alias account'),
														'value' => $alias);
	}

	my $dn = "mail=$alias, " . $self->aliasDn();

	#if is the last maildrop delete the alias account
	my @mlist = @{$self->accountListByAliasGroup($alias)};
	my %attrs;

	if (@mlist == 1) {
		$self->delAlias($alias);
	} else {
		%attrs = (
			changes => [
				delete => [ 'maildrop'	=> $maildrop ]
			]
		);
		my $r = $self->{'ldap'}->modify($dn, \%attrs);
	}	

}

# Method: delAlias
#
#	This method removes a mail alias account
#
# Parameters:
#
#     alias - The mail alias account to create
sub delAlias($$) { #mail alias account
	my $self = shift;
	my $alias = shift;

	unless ($self->aliasExists($alias)) {
		throw EBox::Exceptions::DataNotFound('data' => __('mail alias account'),
														'value' => $alias);
	}

	# We Should warn about users whose mail account belong to this vdomain.

	my $r = $self->{'ldap'}->delete("mail=$alias, " . $self->aliasDn);
}

# Method: delAliasesFromVDomain
#
#	This method removes all mail aliases from a virtual domain
#
# Parameters:
#
#		vdomain - The Virtual domain name
sub delAliasesFromVDomain () {
	my ($self, $vdomain) = @_;

	my @aliases = @{$self->_allAliasFromVDomain($vdomain)};

	foreach (@aliases) {
		$self->delAlias($_);
	}

}

# Method: delAliasGroup
#
#	This method removes the mail alias account of a group
#
# Parameters:
#
#     group - The group name
sub delAliasGroup($$) {
	my ($self, $group) = @_;

	my %args = (
		base => $self->aliasDn,
		filter => "&(objectclass=couriermailalias)(userid=$group)",
		scope => 'one',
		attrs => ['mail']
	);
	
	my $result = $self->{ldap}->search(\%args);

	if ($result->count > 0) {
		my $alias = ($result->sorted('mail'))[0]->get_value('mail');
		$self->delAlias($alias);
	}
}

# Method: accountAlias
#
#	This method returns all mail alias accounts that have a mail account of
#	a user
#
# Parameters:
#
#     mail - The mail account 
sub accountAlias($$) { #mail account
	my $self = shift;
	my $mail = shift;

	my %args = (
		base => $self->aliasDn,
		filter => "&(userid=$mail)(maildrop=$mail)",
		scope => 'one',
		attrs => ['mail']
	);
	
	my $result = $self->{ldap}->search(\%args);

	my @malias = ();
	foreach my $alias ($result->sorted('mail'))
	{
		@malias = (@malias, $alias->get_value('mail'));
	}

	return @malias;
}

# Method: groupAccountAlias
#
#	This method returns all mail alias accounts that have a mail account of
#	a group
#
# Parameters:
#
#     mail - The mail account 
sub groupAccountAlias($$) { #mail account
	my $self = shift;
	my $mail = shift;

	my %args = (
		base => $self->aliasDn,
		filter => "&(!(userid=$mail))(maildrop=$mail)",
		scope => 'one',
		attrs => ['mail']
	);
	
	my $result = $self->{ldap}->search(\%args);

	my @malias = ();
	foreach my $alias ($result->sorted('mail'))
	{
		@malias = (@malias, $alias->get_value('mail'));
	}

	return @malias;
}

# Method: accountListByAliasGroup
#
#	This method returns an array ref with all maildrops of a group alias account
#
# Parameters:
#
#     mail - The mail aliasaccount 
# Returns:
# 		array ref - Array that contains mail accounts
sub accountListByAliasGroup() {
	my ($self, $mail) = @_;

	my %args = (
		base => $self->aliasDn,
		filter => "(mail=$mail)",
		scope => 'one',
		attrs => ['maildrop']
	);
	
	my $result = $self->{ldap}->search(\%args);

	my @mlist = map { $_->get_value('maildrop') } $result->sorted('uid');

	return \@mlist;
}

# Method: aliasDn
#
#	This method returns the DN of alias ldap leaf
#
# Returns:
#
#     string - DN of alias leaf
sub aliasDn
{
	my $self = shift;
	return ALIASDN . ", " . $self->{ldap}->dn;
}

# Method: listMailGroupsByUser
#
#	This method returns all groups whith an alias account which the user passed
#	as parameter belongs.
#
# Parameters:
#
#     user - usename 
#     
# Returns:
# 
# 		array - With the group's name list
sub listMailGroupsByUser($$) {
	my ($self, $user) = @_;
	my @list;
	my $users = EBox::Global->modInstance('users');

	my @groups = @{$users->groupOfUsers($user)};
	
	foreach my $group (@groups) {
		if ($self->groupHasAlias($group)) {
			push(@list, $group);
		}
	}
	return @list;
}

# Method: groupAlias
#
#	This method returns the mail alias account of a group
#
# Parameters:
#
#     group - The group name
#
# Returns:
# 		string - mail alias account
sub groupAlias ($$) {
	my ($self, $group) = @_;

	my %args = (
		base => $self->aliasDn,
		filter => "&(objectclass=couriermailalias)(uid=$group)",
		scope => 'one',
		attrs => ['mail']
	);
	
	my $result = $self->{ldap}->search(\%args);

	return (($result->sorted('mail'))[0]->get_value('mail'));
}

# Method: groupHasAlias
#
#	This method returns if the group has a mail alias account
#
# Parameters:
#
#     group - The group name
#
# Returns:
# 	
# 		true if the group has an account, false otherwise
sub groupHasAlias ($$) {
	my ($self, $group) = @_;

	my %args = (
		base => $self->aliasDn,
		filter => "&(objectclass=couriermailalias)(uid=$group)",
		scope => 'one',
		attrs => ['mail']
	);
	
	my $result = $self->{ldap}->search(\%args);

	return ($result->count > 0);
}

# Method: aliasExists
#
#	This method returns wether a given alias exists
#
# Parameters:
#
#     mail - The mail account 
sub aliasExists($$) { #mail alias 
	my $self = shift;
	my $alias = shift;

	my %attrs = (
		base => $self->aliasDn,
		filter => "&(objectclass=couriermailalias)(mail=$alias)",
		scope => 'one'
	);

	my $result = $self->{'ldap'}->search(\%attrs);

	return ($result->count > 0);
}

# Method: accountExists
#
#	This method returns an account exists like an alias account or mail account
#
# Parameters:
#
#     mail - The mail account 
#
# Returns
#
# 		true if the account exists, false otherwise
sub accountExists($$) { #mail alias account
	my $self = shift;
	my $alias = shift;
	my $users = EBox::Global->modInstance('users');

	my %attrs = (
		base => $users->usersDn,
		filter => "&(objectclass=couriermailaccount)(mail=$alias)",
		scope => 'one'
	);

	my $result = $self->{'ldap'}->search(\%attrs);

	return (($result->count > 0) || ($self->aliasExists($alias)));
}

# Method: _allAliasFromVDomain
#
#	This method returns all mail alias accounts and domain aliases from/for
#	 a virtual domain
#
# Parameters:
#
#     vdomain - The Virtual domain name
#
# Returns:
# 		
# 		array ref - with all alias account from a virtual domain.
sub _allAliasFromVDomain () { #vdomain
	my ($self, $vdomain) = @_;

	my %attrs = (
		base => $self->aliasDn,
		filter => "&(objectclass=couriermailalias)(mail=*@".$vdomain.")",
		scope => 'one'
	);

	my $result = $self->{'ldap'}->search(\%attrs);

	my @alias = map { $_->get_value('mail')} $result->sorted('mail');

        push @alias, @{ $self->vdomainAliases($vdomain)  };

	return \@alias;
}


sub _syncAliasTable
{
    my ($self, $vdomain, $aliasTable) = @_;

    my %aliasToDelete = map { $_ => 1 } @{ $self->vdomainAliases($vdomain) };


    foreach my $id (@{ $aliasTable->ids() }) {
        my $row = $aliasTable->row($id);
        my $alias     = $row->valueByName('alias');
        my $fullAlias = '@' . $alias;


        if (not $self->aliasExists($fullAlias)) {
            $self->addVDomainAlias($vdomain, $alias);
        }

        delete $aliasToDelete{$fullAlias};
    }


    # alias no present in the table must be deleted
    foreach my $alias (keys %aliasToDelete) {
        $self->delAlias($alias);
    }
}


1;
