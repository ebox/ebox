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

package EBox::Jabber;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::LdapModule EBox::FirewallObserver);

use EBox::Exceptions::DataExists;
use EBox::Gettext;
use EBox::JabberFirewall;
use EBox::JabberLdapUser;
use EBox::Ldap;
use EBox::Menu::Item;
use EBox::Network;
use EBox::Service;
use EBox::Sudo qw ( :all );
use EBox::Summary::Module;
use EBox::Summary::Status;
use EBox::Validate qw ( :all );

use constant JABBERC2SCONFFILE => '/etc/jabberd2/c2s.xml';
use constant JABBERSMCONFFILE => '/etc/jabberd2/sm.xml';
use constant JABBERPORT => '5222';
use constant JABBERPORTSSL => '5223';

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'jabber',
					  domain => 'ebox-jabber',
					  @_);
	bless($self, $class);
	return $self;
}

sub daemons # (action)
{
	my ($self, $action) = @_;
	
	if ($action eq 'start') {
	      EBox::Service::manage('jabber-router', $action);
	      EBox::Service::manage('jabber-resolver', $action) if ($self->externalConnection);
	      EBox::Service::manage('jabber-sm', $action);
	      EBox::Service::manage('jabber-c2s', $action);
	      EBox::Service::manage('jabber-s2s', $action) if ($self->externalConnection);
	} elsif ($action eq 'stop'){
	      EBox::Service::manage('jabber-s2s', $action);
	      EBox::Service::manage('jabber-c2s', $action);
	      EBox::Service::manage('jabber-sm', $action);
  	      EBox::Service::manage('jabber-resolver', $action);
	      EBox::Service::manage('jabber-router', $action);
	} else {
  	      $self->daemons('stop');
	      $self->daemons('start');
	}

}

sub _doDaemon
{
	my $self = shift;

	if ($self->service and EBox::Service::running('jabber-c2s')) {
		$self->daemons('restart');
	} elsif ($self->service) {
		$self->daemons('start');
	} elsif (EBox::Service::running('jabber-c2s')){
		$self->daemons('stop');
	}
}

sub usesPort # (protocol, port, iface)
{
	my ($self, $protocol, $port, $iface) = @_;

	return undef unless($self->service());

	return 1 if (($port eq JABBERPORT) and !($self->ssl eq 'required'));
	return 1 if (($port eq JABBERPORTSSL) and !($self->ssl eq 'no'));

	return undef;
}

sub firewallHelper
{
	my $self = shift;
	if ($self->service){
		return new EBox::JabberFirewall();
	}
	return undef;
}

sub setExternalConnection
{
    my ($self, $external) = @_;
    ($external == $self->externalConnection) and return;
    $self->set_bool('external_connection', $external);
}

sub externalConnection
{
    my $self = shift;
    return $self->get_bool('external_connection');
}

sub setSsl
{
    my ($self, $ssl) = @_;
    ($ssl eq $self->ssl) and return;
    $self->set_string('ssl', $ssl);
}

sub ssl
{
    my $self = shift;
    return $self->get_string('ssl');
}

sub setService
{
	my ($self, $active) = @_;
	($active and $self->service) and return;
	(!$active and !$self->service) and return;

	if ($active) {
		if (not $self->service){
			my $fw = EBox::Global->modInstance('firewall');
			my $port = JABBERPORT;
			unless ($fw->availablePort('tcp', $port) and
				$fw->availablePort('udp', $port)){
					throw EBox::Exceptions::DataExists(
						'data' => __('listening port'),
						'value' => $port);
				}
		}
	}
	$self->set_bool('active', $active);
}

sub service
{
	my $self = shift;
	return $self->get_bool('active');
}

sub setDomain
{
	my ($self, $domain) = @_;
	unless (checkDomainName($domain)){
		throw EBox::Exceptions::InvalidData
			('data' => __('domain'), 'value' => $domain);
	}
	($domain eq $self->domain) and return;
	$self->set_string('domain', $domain);
}

sub domain
{
	my $self = shift;
	return $self->get_string('domain');
}

sub _regenConfig
{
	my $self = shift;

	$self->_setJabberConf;
	$self->_doDaemon();
}

sub _setJabberConf
{
	my $self = shift;
	my @array = ();

	my $net = EBox::Global->modInstance('network');
	my $ldap = new EBox::Ldap;
	my $ldapconf = $ldap->ldapConf;

	push (@array, 'domain' => $self->domain);
	push (@array, 'binddn' => $ldapconf->{'rootdn'});
	push (@array, 'bindpw' => $ldap->rootPw);
	push (@array, 'basedc' => $ldapconf->{'dn'});
	push (@array, 'ssl' => $self->ssl);

	$self->writeConfFile(JABBERC2SCONFFILE,
			     "jabber/c2s.xml.mas",
			     \@array);

	@array = ();

	push (@array, 'domain' => $self->domain);

	$self->writeConfFile(JABBERSMCONFFILE,
			     "jabber/sm.xml.mas",
			     \@array);
}

sub statusSummary
{
	my $self = shift;
	return new EBox::Summary::Status('jabber', __('Jabber'),
		EBox::Service::running('jabber-c2s'), $self->service);
}

#sub summary
#{
#	my $self = shift;
#	my $item = new EBox::Summary::Module(__("Jabber service"));
#	
#	return $item;
#}

sub rootCommands
{
	my $self = shift;
	my @array = ();
	push(@array, $self->rootCommandsForWriteConfFile(JABBERC2SCONFFILE));
	push(@array, $self->rootCommandsForWriteConfFile(JABBERSMCONFFILE));
	return @array;
}

sub menu
{
	my ($self, $root) = @_;
	$root->add(new EBox::Menu::Item('url' => 'Jabber/Index',
					'text' => __('Jabber Service')));
}

sub _ldapModImplementation
{
    my $self;

    return new EBox::JabberLdapUser();
}
1;
