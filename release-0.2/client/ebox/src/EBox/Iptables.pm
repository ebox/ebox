# Copyright (C) 2004  Warp Netwoks S.L.
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
use EBox::Objects;
use EBox::Network;
use EBox::Exceptions::Internal;
use EBox::Sudo qw( :all );
use Data::Dumper;


my $new = " -m state --state NEW ";


sub new {
	my $class = shift;
	my $self = {};
	$self->{firewall} = EBox::Global->modInstance('firewall');
	$self->{objects} = EBox::Global->modInstance('objects');
	$self->{net} = EBox::Global->modInstance('network');
	$self->{deny} = $self->{firewall}->denyAction;
	bless($self, $class);
	return $self;
}

sub pf($) {
	my $opts = shift;
	root("/sbin/iptables $opts");
}

sub startIPForward() {
	root('/sbin/sysctl -q -w net.ipv4.ip_forward="1"');
}

sub stopIPForward() {
	root('/sbin/sysctl -q -w net.ipv4.ip_forward="0"');
}


sub clearTables($$) {
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

sub Object($$) {
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
		my $addresses = $self->{objects}->getObjectAddresses($object);
		defined($addresses) or return;
		foreach (@{$addresses}) {
			pf "-A fobjects $new -s $_ -j $fchain";
			pf "-A iobjects $new -s $_ -j $ichain";
		}
	}

	my $servs = $self->{firewall}->ObjectServices($object);
	unless (defined($servs)) {
		my @array = ();
		$servs = \@array;
	}
	foreach my $srv (@{$servs}) {
		defined($srv) or next;
		my $policy;
		if ($srv->{policy} eq "deny") {
			$policy = "idrop";
		} elsif ($srv->{policy} eq "allow") {
			$policy = "ACCEPT";
		} else {
			throw EBox::Exceptions::Internal("Iptables: object $object".
				", unknown policy ". $srv->{policy} . 
				" for service " . $srv->{name});
		}
		my $port = $self->{firewall}->servicePort($srv->{name});
		defined($port) or next;
		my $protocol = $self->{firewall}->serviceProtocol($srv->{name});
		defined($protocol) or next;
		pf "-A $ichain $new -p $protocol --dport $port -j $policy";
	}

	my $rules = $self->{firewall}->ObjectRules($object);
	unless (defined($rules)) {
		my @array = ();
		$rules = \@array;
	}
	foreach my $rule (@{$rules}) {
		defined($rule) or next;
		if ($rule->{active} != 1) {
			next;
		}
		my $port = $rule->{port};
		defined($port) or next;
		my $protocol = $rule->{protocol};
		defined($protocol) or next;
		my $address = $rule->{address};
		my $mask = $rule->{mask};
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

		my $aux = "";
		if (defined($address)) {
			$aux = " -d $address";
			if (defined($mask)) {
				$aux .= "/$mask";
			}
			$aux .= " ";
		}

		pf "-A $fchain $new -p $protocol --dport $port $aux -j $action";
	}
	
	my $policy = $self->{firewall}->ObjectPolicy($object);
	my $aux;
	if ($policy eq "allow") {
		$aux = "-j ACCEPT";;
	} elsif ($policy eq "deny") {
		$aux = "-j fdrop";
	} elsif ($policy eq "global") {
		return;
	} else {
		throw EBox::Exceptions::Internal("Iptables: ".
			"unknown policy $policy for object $object");
	}

	pf "-A $fchain $new $aux";
}

sub setStructure($) {
	my $self = shift;
	$self->clearTables("DROP");

	# state rules
	pf '-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT';
	pf '-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT';
	pf '-A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT';

	# loopback
	pf '-A INPUT -i lo -j ACCEPT';
	pf '-A OUTPUT -o lo -j ACCEPT';

	# FIXME, let's allow icmp for now, make a decission about this
	pf '-A OUTPUT -p icmp ! -f -j ACCEPT';
	pf '-A INPUT -p icmp ! -f -j ACCEPT';
	pf '-A FORWARD -p icmp ! -f -j ACCEPT';

	pf '-N fnospoof';
	pf '-N fredirects';
	pf '-N fprecustom';
	pf '-N fobjects';
	pf '-N fpostcustom';
	pf '-N fglobal';
	pf '-N fdrop';

	pf '-N inospoof';
	pf '-N iobjects';
	pf '-N iglobal';
	pf '-N idrop';

	pf '-A FORWARD -j fnospoof';
	pf '-A FORWARD -j fredirects';
	pf '-A FORWARD -j fprecustom';
	pf '-A FORWARD -j fobjects';
	pf '-A FORWARD -j fpostcustom';
	pf '-A FORWARD -j fglobal';
	pf '-A FORWARD -j fdrop';

	pf '-A INPUT -j inospoof';
	pf '-A INPUT -j iobjects';
	pf '-A INPUT -j iglobal';
	pf '-A INPUT -j idrop';

	pf "-A idrop -j " . $self->{deny};
	pf "-A fdrop -j " . $self->{deny};
}

sub setDNS($$) {
	my $self = shift;
	my $dns = shift;
	pf "-A OUTPUT $new -p udp --dport 53 -d $dns -j ACCEPT";
	pf "-A fglobal $new -p udp --dport 53 -d $dns -j ACCEPT";
}

sub nospoof($$$) {
	my $self = shift;
	my ($iface, $network) = @_;
	pf "-A fnospoof -s $network -i ! $iface -j fdrop";
	pf "-A inospoof -s $network -i ! $iface -j fdrop";
	pf "-A inospoof -i $iface -d ! $network -j idrop";
}

sub redirect($$$$$$) {
	my $self = shift;
	my ($proto, $inport, $address, $iface, $dport) = @_;
	my $opts = "-t nat -A PREROUTING -i " . $iface . " ";
	if ($self->{net}->ifaceMethod($iface) eq 'static') {
		$opts .= " -d " . $self->{net}->ifaceAddress($iface) . " ";
	}
	$opts .= "-p $proto --dport $inport -j DNAT --to $address:$dport";
	pf $opts;
	pf " -A fredirects $new -p $proto --dport $dport -d $address -i " .
	    $iface . " -j ACCEPT";
}

sub stop($) {
	my $self = shift;
	stopIPForward();
	$self->clearTables("ACCEPT");
}

sub start($) {
	my $self = shift;

	$self->setStructure();

	my @dns = @{$self->{net}->nameservers()};
	foreach (@dns) {
		$self->setDNS($_);
	}

	foreach ($self->{objects}->getObjectNames) {
		my $members = $self->{objects}->getObjectMembers($_);
		foreach (@{$members}) {
			my $mac = $_->{mac};
			defined($mac) or next;
			($mac ne "") or next;
			my $address = $_->{ip} . "/" . $_->{mask};
			pf "-A inospoof -m mac -s $address " .
			   "--mac-source ! $mac -j idrop";
			pf "-A fnospoof -m mac -s $address " .
			   "--mac-source ! $mac -j fdrop";
			pf "-A inospoof -m mac -s ! $address " .
			   "--mac-source $mac -j idrop";
			pf "-A fnospoof -m mac -s ! $address " .
			   "--mac-source $mac -j fdrop";
		}
	}

	my @ifaces = @{$self->{net}->ifaces()};
	foreach (@ifaces) {
		if ($self->{net}->ifaceMethod($_) ne 'static') {
			next;
		}
		my $addr = $self->{net}->ifaceAddress($_);
		my $mask = $self->{net}->ifaceNetmask($_);
		$self->nospoof($_, "$addr/$mask");
	}

	my $redirects = $self->{firewall}->portRedirections;
	if ($redirects) {
		foreach (@{$redirects}) {
			$self->redirect($_->{'protocol'},
					$_->{'eport'},
					$_->{'ip'},
					$_->{'iface'},
					$_->{'dport'});
		}
	}

	@ifaces = @{$self->{net}->getExternalIfaces()};
	foreach (@ifaces) {
		pf "-A fredirects $new -i " . $_ . " -j fdrop";
		if ($self->{net}->ifaceMethod($_) eq 'static') {
			my $addr = $self->{net}->ifaceAddress($_);
			pf "-t nat -A POSTROUTING -s ! $addr -o $_ " .
			   "-j SNAT --to $addr"
		} elsif ($self->{net}->ifaceMethod($_) eq 'dhcp') {
			pf "-t nat -A POSTROUTING -o $_ -j MASQUERADE";
		}
	}

	my $rules = $self->{firewall}->OutputRules();
	unless (defined($rules)) {
		my @array = ();
		$rules = \@array;
	}
	foreach my $rule (@{$rules}) {
		defined($rule) or next;
		my $port = $rule->{port};
		my $proto = $rule->{protocol};
		pf "-A OUTPUT $new  -p $proto --dport $port -j ACCEPT";
	}

	foreach ($self->{firewall}->ObjectNames) {
		$self->Object($_);
	}

	my $servs = $self->{firewall}->services();
	unless (defined($servs)) {
		my @array = ();
		$servs = \@array;
	}
	foreach my $srv (@{$servs}) {
		if (defined($srv->{dnatport})) {
			my $dnatport = $srv->{dnatport};
			my $port = $srv->{port};
			my $protocol = $srv->{protocol};
			my $aux = "";
			@ifaces = @{$self->{net}->getInternalIfaces()};
			foreach (@ifaces) {
				pf "-t nat -A PREROUTING -i $_ -p $protocol " .
				   "--dport $dnatport -j REDIRECT --to-ports " .
				   "$port";
			}
		}
	}


	startIPForward();
}

1;
