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

use Error qw(:try);

use constant DN            => "dc=ebox";
use constant LDAPI         => "ldapi://%2fvar%2frun%2fldapi";
use constant SLAPDCONFFILE => "/etc/ldap/slapd.conf";
use constant ROOTDN        => 'cn=admin,' . DN;

sub new {
	my $class = shift;
	
	my $self = {};
	$self->{ldap} = undef;
	bless($self, $class);
	return $self;
}

sub ldapCon {
	my $self = shift;

	return $self->{ldap} if ($self->{ldap});

	$self->{ldap} = Net::LDAP->new (LDAPI)
			or throw EBox::Exceptions::Internal( 
					"Can't create ldapi connection");
	$self->{ldap}->bind(ROOTDN, password => getPassword());

	return $self->{ldap};
}

sub getPassword {

	my $path = EBox::Config->conf . "/ebox-ldap.passwd";
        open(PASSWD, $path) or
                throw EBox::Exceptions::Internal("Could not open $path to " .
						 "get ldap password");

        my $pwd = <PASSWD>;
        close(PASSWD);

        $pwd =~ s/[\n\r]//g;

	return $pwd;
}


sub dn {
	return DN;
}

sub rootDn {
	return ROOTDN
}

sub rootPw {
	return getPassword();
}

sub slapdConfFile {
	return SLAPDCONFFILE;
}

sub ldapConf {
	shift;
	
	my $conf = {
		     'dn'     => DN,
		     'ldapi'  => LDAPI,
		     'rootdn' => ROOTDN,
		   };
	return $conf;
}

sub search($$) {
	my $self = shift;
	my $args = shift;

	$self->ldapCon;	
	my $result = $self->{ldap}->search(%{$args});
	_errorOnLdap($result, $args);
	return $result;
	
}

sub modify($$) {
	my $self = shift;
	my $dn   = shift;
	my $args = shift;

	$self->ldapCon;	
	my $result = $self->{ldap}->modify($dn, %{$args});
	_errorOnLdap($result, $args);
	return $result;

}

sub delete($$) {
	my $self = shift;
	my $dn   = shift;
	
	$self->ldapCon;	
	my $result =  $self->{ldap}->delete($dn);
	_errorOnLdap($result, $dn);
	return $result;

}

sub add($$) {
	my $self = shift;
	my $dn   = shift;
	my $args = shift;
	
	$self->ldapCon;	
	my $result =  $self->{ldap}->add($dn, %{$args});
	_errorOnLdap($result, $args);
	return $result;
}


sub _errorOnLdap($;$) 
{
        my $result = shift;
        my $args   = shift;

        my  @frames = caller (2);
        if ($result->is_error){
                if ($args) {
			use Data::Dumper;
			print STDERR Dumper($args);
                }
                throw EBox::Exceptions::Internal("Unknown error at " .
						$frames[3] . " " .
						$result->error);
        }
}

1;
