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

package EBox::Mail;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::LdapModule EBox::ObjectsObserver);

use Proc::ProcessTable;
use EBox::Sudo qw( :all );
use EBox::Gettext;
use EBox::Summary::Module;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::MailVDomainsLdap;
use EBox::MailUserLdap;
use EBox::MailAliasLdap;

use constant MAILMAINCONFFILE			=> '/etc/postfix/main.cf';
use constant MAILMASTERCONFFILE			=> '/etc/postfix/master.cf';
use constant AUTHLDAPCONFFILE			=> '/etc/courier/authldaprc';
use constant AUTHDAEMONCONFFILE			=> '/etc/courier/authdaemonrc';
use constant POP3DCONFFILE			=> '/etc/courier/pop3d';
use constant POP3DSSLCONFFILE			=> '/etc/courier/pop3d-ssl';
use constant IMAPDCONFFILE			=> '/etc/courier/imapd';
use constant IMAPDSSLCONFFILE			=> '/etc/courier/imapd-ssl';
use constant MAILINIT				=> '/etc/init.d/postfix';
use constant POPINIT				=> '/etc/init.d/courier-pop';
use constant POPSSLINIT				=> '/etc/init.d/courier-pop-ssl';
use constant IMAPINIT				=> '/etc/init.d/courier-imap';
use constant IMAPSSLINIT				=> '/etc/init.d/courier-imap-ssl';
use constant AUTHDAEMONINIT			=> '/etc/init.d/courier-authdaemon';
use constant AUTHLDAPINIT			=> '/etc/init.d/courier-ldap';
use constant POPPIDFILE				=> "/var/run/courier/pop3d.pid";
use constant POPSSLPIDFILE				=> "/var/run/courier/pop3d-ssl.pid";
use constant IMAPPIDFILE			=> "/var/run/courier/imapd.pid";
use constant IMAPSSLPIDFILE			=> "/var/run/courier/imapd-ssl.pid";
use constant BYTES				=> '1048576';

sub _create 
{
	my $class = shift;
	my $self = $class->SUPER::_create(name => 'mail',
					domain => 'ebox-mail',
					@_);

	$self->{vdomains} = new EBox::MailVDomainsLdap;
	$self->{musers} = new EBox::MailUserLdap;
	$self->{malias} = new EBox::MailAliasLdap;
	
	bless($self, $class);
	return $self;
}

sub _setMailConf {
	my $self = shift;
	my @array = ();
	my $users = EBox::Global->modInstance('users');
	my $ob = EBox::Global->modInstance('objects');
	my $allowedaddrs = "127.0.0.0/8";

	foreach my $obj (@{$self->allowedObj}) {
		foreach my $addr (@{$ob->ObjectAddresses($obj)}) {
			$allowedaddrs .= " $addr";
		}
	}

	push(@array, 'ldapi', $self->{vdomains}->{ldap}->ldapConf->{ldapi});
	push(@array, 'vdomainDN', $self->{vdomains}->vdomainDn());
	push(@array, 'relay', $self->relay());
	push(@array, 'maxmsgsize', ($self->getMaxMsgSize() * $self->BYTES));
	push(@array, 'allowed', $allowedaddrs);
	push(@array, 'aliasDN', $self->{malias}->aliasDn());
	push(@array, 'vmaildir', $self->{musers}->DIRVMAIL);
	push(@array, 'usersDN', $users->usersDn());
	push(@array, 'uidvmail', $self->{musers}->uidvmail());
	push(@array, 'gidvmail', $self->{musers}->gidvmail());
	push(@array, 'sasl', $self->service('sasl'));
	push(@array, 'smtptls', $self->service('smtptls'));
	push(@array, 'popssl', $self->service('popssl'));
	push(@array, 'imapssl', $self->service('imapssl'));
	$self->writeConfFile(MAILMAINCONFFILE, "mail/main.cf.mas", \@array);

	@array = ();
	push(@array, 'smtptls', $self->service('smtptls'));
	$self->writeConfFile(MAILMASTERCONFFILE, "mail/master.cf.mas", \@array);

	@array = ();
	push(@array, 'usersDN', $users->usersDn());
	push(@array, 'rootDN', $self->{vdomains}->{ldap}->rootDn());
	push(@array, 'rootPW', $self->{vdomains}->{ldap}->rootPw());
	
	$self->writeConfFile(AUTHLDAPCONFFILE, "mail/authldaprc.mas", \@array);
	
	$self->writeConfFile(AUTHDAEMONCONFFILE, "mail/authdaemonrc.mas");
	$self->writeConfFile(IMAPDCONFFILE, "mail/imapd.mas");
	$self->writeConfFile(POP3DCONFFILE, "mail/pop3d.mas");
	$self->writeConfFile(POP3DSSLCONFFILE, "mail/pop3d-ssl.mas");
	$self->writeConfFile(IMAPDSSLCONFFILE, "mail/imapd-ssl.mas");
	
}

sub isRunning
{
	my ($self, $service) = @_;
	if ($service eq 'active') {
		my $t = new Proc::ProcessTable;
		foreach my $proc (@{$t->table}) {
			($proc->fname eq 'master') and return 1;
		}
	} elsif ($service eq 'pop') {
		return $self->pidFileRunning(POPPIDFILE);
	} elsif ($service eq 'popssl') {
		return $self->pidFileRunning(POPSSLPIDFILE);
	} elsif ($service eq 'imap') {
		return $self->pidFileRunning(IMAPPIDFILE);
	} elsif ($service eq 'imapssl') {
		return $self->pidFileRunning(IMAPSSLPIDFILE);
	} else {
		return undef;
	}
}

sub setRelay #(smarthost)
{
	my ($self, $relay) = @_;
	$self->set_string('relay', $relay);
}

sub relay
{
	my $self = shift;
	return $self->get_string('relay');
}

sub setMaxMsgSize
{
	my ($self, $size)  = @_;
	$self->set_int('maxmsgsize', $size);
}

sub getMaxMsgSize
{
	my $self = shift;
	return $self->get_int('maxmsgsize');
}

sub setMDDefaultSize
{
	my ($self, $size)  = @_;
	print STDERR "FOO: $size";
	$self->set_int('mddefaultsize', $size);
}

sub getMDDefaultSize
{
	my $self = shift;
	return $self->get_int('mddefaultsize');
}

sub setAllowedObj
{
	my ($self, $args) = @_;
	($args) or return;
	$self->set_list("allowed", "string", $args);
}

#
# Method: allowedObj
#
#  Returns the list of allowed objects to relay mail.
#
# Returns:
#
#  array ref - holding the objects
#
sub allowedObj
{
	my $self = shift;
	return $self->get_list('allowed');
}

#
# Method: isAllowed
#
#  Checks if a given object is allowed to relay mail.
#
# Parameters:
#
#  object - object name
#
# Returns:
#
#  boolean - true if it's set as allowed, otherwise false
#
sub isAllowed
{
	my ($self, $object)  = @_;
   my @allowed = @{$self->allowedObj};
	(@allowed) or return;
   foreach (@allowed) {
      return 1 if ($_ eq $object);
   }
   return undef;
}

#
# Method: deniedObj
#
#  Returns the list of objects that cant relay mail.
#
# Returns:
#
#  array ref - holding the objects
#
sub deniedObj
{
	my $self = shift;
	my @denied = ();
	my $object = EBox::Global->modInstance('objects');

	my @objects = @{$object->ObjectNames};

	foreach (@objects) {
		if ($self->isAllowed($_)) {
			next;
		}
		push(@denied, $_);
	}
	return \@denied;
}

sub freeObject # (object)
{
   my ($self, $object) = @_;
   (defined($object) && $object ne "") or return;

   my @allowedobjs= @{$self->allowedObj};

   if (grep(/^$object$/, @allowedobjs)) {
      my @array = ();
      foreach (@allowedobjs) {
         ($_ ne $object) or next;
         push(@array, $_)
      }
      $self->setAllowedObj(\@array);
   }
}

sub usesObject # (object)
{
	my ($self, $object) = @_;
	if ($self->isAllowed($object)) {
		return 1;
	}
	return undef;
}

sub _doDaemon
{
        my ($self, $service) = @_;
        if ($self->service($service) and $self->isRunning($service)) {
                $self->_daemon('restart', $service);
        } elsif ($self->service($service)) {
                $self->_daemon('start', $service);
        } elsif ($self->isRunning($service)) {
                $self->_daemon('stop', $service);
        }
}

sub _command
{
	my ($self, $action, $service) = @_;
	my $cmd = undef;

	if ($service eq 'active') {
		$cmd = MAILINIT . " " . $action . " 2>&1";
	} elsif ($service eq 'pop') {
		$cmd = POPINIT . " " . $action . " 2>&1";
	} elsif ($service eq 'popssl') {
		$cmd = POPSSLINIT . " " . $action . " 2>&1";
	} elsif ($service eq 'imap') {
		$cmd = IMAPINIT . " " . $action . " 2>&1";
	} elsif ($service eq 'imapssl') {
		$cmd = IMAPSSLINIT . " " . $action . " 2>&1";
	} elsif ($service eq 'authdaemon') {
		$cmd = AUTHDAEMONINIT . " " . $action . " 2>&1";
	} elsif ($service eq 'authldap') {
		$cmd = AUTHLDAPINIT . " " . $action . " 2>&1";
	} else {
		throw EBox::Exceptions::Internal("Bad service: $service");
	}

	return $cmd;
}		

sub _daemon
{
	my ($self, $action, $service) = @_;

	my $command = $self->_command($action, $service);
	
	if ( $action eq 'start') {
		root($command);
	} elsif ( $action eq 'stop') {
		root($command);
	} elsif ( $action eq 'reload') {
		root($command);
	} elsif ( $action eq 'restart') {
		root($command);
	} else {
		throw EBox::Exceptions::Internal("Bad argument: $action");
	}
}

sub _stopService
{
	my $self = shift;
	if ($self->isRunning('active')) {
		$self->_daemon('stop', 'active');
	}
}

sub _regenConfig
{
	my $self = shift;
	my @services = ('active', 'pop', 'popssl', 'imap', 'imapssl');
	$self->_setMailConf;

	foreach (@services) {
		$self->_doDaemon($_);
	}

	$self->_daemon('restart', 'authdaemon');
	$self->_daemon('restart', 'authldap');
}

#
# Method: setService
#
#  Enable/Disable the service passes as parameter.
#
# Parameters:
#
#  active - true or false
#  service - the service to enable or disable.
#
sub setService 
{
        my ($self, $active, $service) = @_;
        ($active and $self->service($service)) and return;
        (!$active and !$self->service($service)) and return;
        $self->set_bool($service, $active);
}

#
# Method: service
#
#  Returns the state of the service passed as parameter
#
# Parameters:
#
#  service - the service
#
# Returns:
#
#  boolean - true if it's active, otherwise false
#
sub service
{
	my ($self, $service) = @_;
	defined($service) or $service = 'active';
	return $self->get_bool($service);
}

# LdapModule implmentation    
sub _ldapModImplementation    
{
	my $self;
        
	return new EBox::MailUserLdap();
}

sub summary
{
	my $self = shift;
	my $item = new EBox::Summary::Module(__("Mail"));
	my $pop = new EBox::Summary::Status('mail', __('POP3 service'),
		$self->isRunning('pop'), $self->service('pop'));
	my $popssl = new EBox::Summary::Status('mail', __('POP3 SSL service'),
		$self->isRunning('popssl'), $self->service('popssl'));
	my $imap = new EBox::Summary::Status('mail', __('IMAP service'),
		$self->isRunning('imap'), $self->service('imap'));
	my $imapssl = new EBox::Summary::Status('mail', __('IMAP SSL service'),
		$self->isRunning('imapssl'), $self->service('imapssl'));

	$item->add($pop);
	$item->add($popssl);
	$item->add($imap);
	$item->add($imapssl);

	return $item;
}

sub rootCommands
{
	my $self = shift;
	my @array = ();
	push(@array, MAILINIT);
	push(@array, POPINIT);
	push(@array, POPSSLINIT);
	push(@array, IMAPINIT);
	push(@array, IMAPSSLINIT);
	push(@array, AUTHDAEMONINIT);
	push(@array, AUTHLDAPINIT);
	push(@array, "/bin/chmod * " . MAILMAINCONFFILE);
	push(@array, "/bin/chown * " . MAILMAINCONFFILE);
	push(@array, "/bin/chmod * " . MAILMASTERCONFFILE);
	push(@array, "/bin/chown * " . MAILMASTERCONFFILE);
	push(@array, "/bin/chmod * " . POP3DCONFFILE);
	push(@array, "/bin/chown * " . POP3DCONFFILE);
	push(@array, "/bin/chmod * " . POP3DSSLCONFFILE);
	push(@array, "/bin/chown * " . POP3DSSLCONFFILE);
	push(@array, "/bin/chmod * " . IMAPDCONFFILE);
	push(@array, "/bin/chown * " . IMAPDCONFFILE);
	push(@array, "/bin/chmod * " . IMAPDSSLCONFFILE);
	push(@array, "/bin/chown * " . IMAPDSSLCONFFILE);
	push(@array, "/bin/chmod * " . AUTHDAEMONCONFFILE);
	push(@array, "/bin/chown * " . AUTHDAEMONCONFFILE);
	push(@array, "/bin/chmod * " . AUTHLDAPCONFFILE);
	push(@array, "/bin/chown * " . AUTHLDAPCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . MAILMAINCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . MAILMASTERCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . POP3DCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . POP3DSSLCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . IMAPDCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . IMAPDSSLCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . AUTHDAEMONCONFFILE);
	push(@array, "/bin/mv " . EBox::Config::tmp . "* " . AUTHLDAPCONFFILE);
	push(@array, "/bin/chmod 2775 /var/mail/");
	push(@array, "/bin/chown ebox.ebox -R /var/vmail/*");
	push(@array, "/bin/chown ebox.ebox /var/vmail/*");
	push(@array, "/bin/mkdir -p /var/vmail*");
	push(@array, "/usr/bin/maildirmake /var/vmail/*");
	push(@array, "/bin/rm -rf /var/vmail/*");

	return @array;
}

sub statusSummary
{
	my $self = shift;
	return new EBox::Summary::Status('mail', __('Mail system'),
		$self->isRunning('active'), $self->service('active'));
}

sub menu
{
	my ($self, $root) = @_;
	my $folder = new EBox::Menu::Folder('name' => 'Mail',
												  'text' => __('Mail'));
	$folder->add(new EBox::Menu::Item('url' => 'Mail/Index',
												'text' => __('General')));
	$folder->add(new EBox::Menu::Item('url' => 'Mail/VDomains',
												'text' => __('Virtual domains')));
	$root->add($folder);
}


1;
