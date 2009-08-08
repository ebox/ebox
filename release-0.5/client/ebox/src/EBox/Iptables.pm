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

package EBox::Iptables;

use EBox::Firewall;
use EBox::Global;
use EBox::Gettext;
use EBox::Objects;
use EBox::Network;
use EBox::Exceptions::Internal;
use EBox::Sudo qw( :all );


my $new = " -m state --state NEW ";


sub new 
{
	my $class = shift;
	my $self = {};
	$self->{firewall} = EBox::Global->modInstance('firewall');
	$self->{objects} = EBox::Global->modInstance('objects');
	$self->{net} = EBox::Global->modInstance('network');
	$self->{deny} = $self->{firewall}->denyAction;
	bless($self, $class);
	return $self;
}

sub pf # (options) 
{
	my $opts = shift;
	root("/sbin/iptables $opts");
}

sub startIPForward
{
	root('/sbin/sysctl -q -w net.ipv4.ip_forward="1"');
}

sub stopIPForward
{
	root('/sbin/sysctl -q -w net.ipv4.ip_forward="0"');
}


sub clearTables # (policy) 
{
	my $self = shift;
	my $policy = shift;
	pf "-F";
	pf "-X";
	pf "-t nat -F";
	pf "-t nat -X";
	pf "-P OUTPUT $policy";
	pf "-P INPUT $policy";
	pf "-P FORWARD $policy";
}

sub Object # (object) 
{
	my $self = shift;
	my $object = shift;
	my $fchain;
	my $ichain;

	if ($object eq "_global") {
		$fchain = "fglobal";
		$ichain = "iglobal";
	} else {
		$fchain = "f_" . $object;
		$ichain = "i_" . $object;
		pf "-N $fchain";
		pf "-N $ichain";
		my $addresses = $self->{objects}->ObjectAddresses($object);
		defined($addresses) or return;
		foreach (@{$addresses}) {
			pf "-A fobjects $new -s $_ -j $fchain";
			pf "-A iobjects $new -s $_ -j $ichain";
		}
	}

	my $servs = $self->{firewall}->ObjectServices($object);
	foreach my $srv (@{$servs}) {
		defined($srv) or next;
		my $policy;
		if ($srv->{policy} eq "deny") {
			$policy = "idrop";
		} elsif ($srv->{policy} eq "allow") {
			$policy = "ACCEPT";
		} else {
			throw EBox::Exceptions::Internal("Iptables: object ".
				"$object, unknown policy ". $srv->{policy} . 
				" for service " . $srv->{name});
		}
		my $port = $self->{firewall}->servicePort($srv->{name});
		defined($port) or next;
		my $protocol = $self->{firewall}->serviceProtocol($srv->{name});
		defined($protocol) or next;
		pf "-A $ichain $new -p $protocol --dport $port -j $policy";
	}

	my $rules = $self->{firewall}->ObjectRules($object);
	foreach my $rule (@{$rules}) {
		defined($rule) or next;
		($rule->{active} == 1) or next;

		my $text = "-A $fchain $new";

		if (defined($rule->{protocol}) and ($rule->{protocol} ne '')) {
			$text .= " -p $rule->{protocol}";

			if (defined($rule->{port}) and ($rule->{port} ne '')) {
				$text .= " --dport $rule->{port}";
			}
		}

		my $action;
		if ($rule->{action} eq "deny") {
			$action = "fdrop";
		} elsif ($rule->{action} eq "allow") {
			$action = "ACCEPT";
		} else {
			throw EBox::Exceptions::Internal("Iptables: ".
				"unknown action " . $rule->{action} .
				" for object $object");
		}

		if (defined($rule->{address}) and ($rule->{address} ne '')) {
			$text .= " -d $rule->{address}";

			if (defined($rule->{mask}) and ($rule->{mask} ne '')) {
				$text .= "/" . $rule->{mask};
			}
			$text .= " -j $action";
			pf $text;
		} else {
			@ifaces = @{$self->{net}->ExternalIfaces()};
			foreach my $if (@ifaces) {
				$text .= " -o $if -j $action";
				pf $text;
			}
		}
	}
	
	my $policy = $self->{firewall}->ObjectPolicy($object);
	my $aux;
	my $ipolicy = undef;
	if ($policy eq "allow") {
		$aux = "-j ftoexternalonly";;
		$ipolicy = 'ACCEPT';
	} elsif ($policy eq "deny") {
		$aux = "-j fdrop";
		$ipolicy = 'idrop';
	} elsif ($policy eq "global") {
		return;
	} else {
		throw EBox::Exceptions::Internal("Iptables: ".
			"unknown policy $policy for object $object");
	}

	pf "-A $ichain $new -j $ipolicy";
	pf "-A $fchain $new $aux";
}

sub setStructure
{
	my $self = shift;
	$self->clearTables("DROP");

	# state rules
	pf '-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT';
	pf '-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT';
	pf '-A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT';

	# loopback
	pf '-A INPUT -i lo -j ACCEPT';
	pf '-A OUTPUT -o lo -j ACCEPT';

	pf '-A OUTPUT -p icmp ! -f -j ACCEPT';
	pf '-A INPUT -p icmp ! -f -j ACCEPT';
	pf '-A FORWARD -p icmp ! -f -j ACCEPT';

	pf '-t nat -N premodules';

	pf '-t nat -N postmodules';

	pf '-N fnospoof';
	pf '-N fredirects';
	pf '-N fmodules';
	pf '-N fnoexternal';
	pf '-N fdns';
	pf '-N fobjects';
	pf '-N fglobal';
	pf '-N fdrop';
	pf '-N ftoexternalonly';

	pf '-N inospoof';
	pf '-N inoexternal';
	pf '-N imodules';
	pf '-N iintservs';
	pf '-N iobjects';
	pf '-N iglobal';
	pf '-N idrop';

	pf '-N omodules';

	pf '-t nat -A PREROUTING -j premodules';

	pf '-t nat -A POSTROUTING -j postmodules';

	pf '-A FORWARD -j fnospoof';
	pf '-A FORWARD -j fredirects';
	pf '-A FORWARD -j fmodules';
	pf '-A FORWARD -j fnoexternal';
	pf '-A FORWARD -j fdns';
	pf '-A FORWARD -j fobjects';
	pf '-A FORWARD -j fglobal';
	pf '-A FORWARD -j fdrop';

	pf '-A INPUT -j inospoof';
	pf '-A INPUT -j inoexternal';
	pf '-A INPUT -j imodules';
	pf '-A INPUT -j iintservs';
	pf '-A INPUT -j iobjects';
	pf '-A INPUT -j iglobal';
	pf '-A INPUT -j idrop';

	pf '-A OUTPUT -j omodules';

	pf "-A idrop -j " . $self->{deny};
	pf "-A fdrop -j " . $self->{deny};
}

sub setDNS # (dns) 
{
	my $self = shift;
	my $dns = shift;
	pf "-A OUTPUT $new -p udp --dport 53 -d $dns -j ACCEPT";
	pf "-A fdns $new -p udp --dport 53 -d $dns -j ACCEPT";
}

sub nospoof # (interface, \@addresses) 
{
	my $self = shift;
	my ($iface, $addreses) = @_;
	foreach (@{$addresses}) {
		my $addr = $_->{address};
		my $mask = $_->{netmask};
		pf "-A fnospoof -s $addr/$mask -i ! $iface -j fdrop";
		pf "-A inospoof -s $addr/$mask -i ! $iface -j idrop";
		pf "-A inospoof -i ! $iface -d $addr -j idrop";
	}
}

sub redirect # (protocol, ext_port, address, interface, dest_port) 
{
	my $self = shift;
	my ($proto, $inport, $address, $iface, $dport) = @_;
	my $extaddr = $self->{net}->ifaceAddress($iface);
	defined($extaddr) or return;
	$extaddr ne '' or return;

	$iface = vifaceRealname($iface);
	my $opts = "-t nat -A PREROUTING -i $iface -d $extaddr ";
	$opts .= "-p $proto --dport $inport -j DNAT --to $address:$dport";
	pf $opts;
	pf " -A fredirects $new -p $proto --dport $dport -d $address -i " .
	    $iface . " -j ACCEPT";
}

sub localRedirects
{
	my $self = shift;
	my $redirects = $self->{firewall}->localRedirects();
	foreach my $redir (@{$redirects}) {
		my $service = $redir->{service};
		my $protocol = $self->{firewall}->serviceProtocol($service);
		my $dport = $self->{firewall}->servicePort($service);
		my $eport = $redir->{port};
		my @ifaces = @{$self->{net}->InternalIfaces()};
		foreach my $ifc (@ifaces) {
			my $addr = $self->{net}->ifaceAddress($ifc);
			(defined($addr) && $addr ne "") or next;
			pf "-t nat -A PREROUTING -i $ifc -p $protocol ".
			   "-d ! $addr --dport $eport " .
			   "-j REDIRECT --to-ports $dport";
			
		}
	}
}

sub doService # (service) 
{
	my ($self, $srv) = @_;
	my $port = $srv->{port};
	my $protocol = $srv->{protocol};
	my $name = $srv->{name};
	if ($self->{firewall}->serviceIsInternal($name)) {
		pf "-A iintservs -p $protocol --dport $port -j ACCEPT";
	}
}

sub stop
{
	my $self = shift;
	stopIPForward();
	$self->clearTables("ACCEPT");
}

sub vifaceRealname # (viface) 
{
	my $virtual = shift;
	$virtual =~ s/:.*$//;
	return $virtual;
}

sub start
{
	my $self = shift;

	$self->setStructure();

	my @dns = @{$self->{net}->nameservers()};
	foreach (@dns) {
		$self->setDNS($_);
	}

	foreach (@{$self->{objects}->ObjectNames}) {
		my $members = $self->{objects}->ObjectMembers($_);
		foreach (@{$members}) {
			my $mac = $_->{mac};
			defined($mac) or next;
			($mac ne "") or next;
			my $address = $_->{ip} . "/" . $_->{mask};
			pf "-A inospoof -m mac -s $address " .
			   "--mac-source ! $mac -j idrop";
			pf "-A fnospoof -m mac -s $address " .
			   "--mac-source ! $mac -j fdrop";
		}
	}

	my @ifaces = @{$self->{net}->ifaces()};
	foreach my $ifc (@ifaces) {
		my $addrs = $self->{net}->ifaceAddresses($ifc);
		$self->nospoof($ifc, $addrs);
		if ($self->{net}->ifaceMethod($ifc) eq 'dhcp') {
			my $dnsSrvs = $self->{net}->DHCPNameservers($ifc);
			foreach my $srv (@{$dnsSrvs}) {
				$self->setDNS($srv);
			}
		}
	}

	my $redirects = $self->{firewall}->portRedirections;
	foreach (@{$redirects}) {
		$self->redirect($_->{'protocol'},
				$_->{'eport'},
				$_->{'ip'},
				$_->{'iface'},
				$_->{'dport'});
	}

	@ifaces = @{$self->{net}->ExternalIfaces()};
	foreach my $if (@ifaces) {
		pf "-A fnoexternal $new -i $if -j fdrop";
		pf "-A inoexternal $new -i $if -j idrop";
		pf "-A ftoexternalonly -o $if -j ACCEPT";

		if ($self->{net}->ifaceMethod($if) eq 'static') {
			my $addr = $self->{net}->ifaceAddress($if);
			pf "-t nat -A POSTROUTING -s ! $addr -o $if " .
			   "-j SNAT --to $addr"
		} elsif ($self->{net}->ifaceMethod($if) eq 'dhcp') {
			pf "-t nat -A POSTROUTING -o $if -j MASQUERADE";
		}
	}
	pf "-A ftoexternalonly -j fdrop";

	my $rules = $self->{firewall}->OutputRules();
	foreach my $rule (@{$rules}) {
		defined($rule) or next;
		my $port = $rule->{port};
		my $proto = $rule->{protocol};
		pf "-A OUTPUT $new  -p $proto --dport $port -j ACCEPT";
	}

	foreach (@{$self->{firewall}->ObjectNames}) {
		$self->Object($_);
	}

	my $servs = $self->{firewall}->services();
	foreach my $srv (@{$servs}) {
		$self->doService($srv);
	}

	$self->localRedirects();

	startIPForward();


	my $global = EBox::Global->getInstance();
	my @modNames = @{$global->modNames}; 
	foreach my $name (@modNames) {
		my $mod = $global->modInstance($name);
		my $helper = $mod->firewallHelper();
		($helper) or next;
		$self->_doRuleset('nat', 'premodules', $helper->prerouting);
		$self->_doRuleset('nat', 'postmodules', $helper->postrouting);
		$self->_doRuleset('filter', 'fmodules', $helper->forward);
		$self->_doRuleset('filter', 'imodules', $helper->input);
		$self->_doRuleset('filter', 'omodules', $helper->output);
	}
}

sub _doRuleset # (table, chain, \@rules)
{
	my ($self, $table, $chain, $rules) = @_;

	foreach my $rule (@{$rules}) {
		pf "-t $table -A $chain $rule";
	}
}


1;
