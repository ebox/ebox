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

package EBox::Iptables;
# Package to manage iptables command utility

# private functions will return references to sets of commands to be run
# instead of running the commands themselves

use strict;
use warnings;

use EBox;
use EBox::Firewall;
use EBox::Config;
use EBox::Global;
use EBox::Gettext;
use EBox::Objects;
use EBox::Network;
use EBox::Firewall::IptablesHelper;
use EBox::Exceptions::External;
use EBox::Exceptions::Internal;
use Error qw( :try );
use EBox::Sudo qw( :all );

my $new = " -m state --state NEW ";

use constant IPT_MODULES => ('ip_conntrack_ftp', 'ip_nat_ftp', 'ip_conntrack_tftp');
use constant SYSLOG_LEVEL => 7;

# Constructor: new
#
#      Create a new EBox::Iptables object
#
# Returns:
#
#      A recently created EBox::Iptables object
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

# Method: pf
#
#       Execute iptables command with options
#
# Parameters:
#
#       opts - options passed to iptables
#
# Returns:
#
#       array ref - the output of iptables command in an array
#
sub pf # (options)
{
    my ($opts) = @_;
    return "/sbin/iptables $opts";
}

# Method: startIPForward
#
#       Change kernel to do IPv4 forwarding (default)
#
# Returns:
#
#       array ref - the output of sysctl command in an array
#
sub _startIPForward
{
    return [ '/sbin/sysctl -q -w net.ipv4.ip_forward="1"' ];
}

# Method: _stopIPForward
#
#       Change kernel to stop doing IPv4 forwarding
#
# Returns:
#
#       array ref - the output of sysctl command in an array
#
sub _stopIPForward
{
    return [ '/sbin/sysctl -q -w net.ipv4.ip_forward="0"' ];
}

# Method: _clearTables
#
#       Clear all tables (user defined and nat), set a policy to
#       OUTPUT, INPUT and FORWARD chains and allow always traffic
#       from/to loopback interface.
#
# Parameters:
#
#       policy - It can be a target
#       (ACCEPT|DROP|REJECT|QUEUE|RETURN|user-defined chain)
#       See iptables TARGETS section
#
sub _clearTables # (policy)
{
    my $self = shift;
    my $policy = shift;
    my @commands;
    push(@commands,
            pf("-F"),
            pf("-X"),
            pf("-t nat -F"),
            pf("-t nat -X"),
        );
# Allow loopback 
    if (($policy eq 'DROP') or ($policy eq 'REJECT')) {
        push(@commands,
                pf('-A INPUT -i lo -j ACCEPT'),
                pf('-A OUTPUT -o lo -j ACCEPT'),
            );
    }
    push(@commands,
            pf("-P OUTPUT $policy"),
            pf("-P INPUT $policy"),
            pf("-P FORWARD $policy"),
        );
    return \@commands;
}

# Method: _setStructure
#
#       Set structure to Firewall module to work
#
sub _setStructure
{
    my ($self) = @_;

    my @commands = ();
    push(@commands,
            @{$self->_clearTables("DROP")}
        );

    # state rules
    push(@commands,
            pf('-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT'),
            pf('-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT'),
            pf('-A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT'),

            pf('-A OUTPUT -p icmp ! -f -j ACCEPT'),
            pf('-A INPUT -p icmp ! -f -j ACCEPT'),
            pf('-A FORWARD -p icmp ! -f -j ACCEPT'),

            pf('-t nat -N premodules'),

            pf('-t nat -N postmodules'),

            pf('-N fnospoof'),
            pf('-N fredirects'),
            pf('-N fmodules'),
            pf('-N ffwdrules'),
            pf('-N fnoexternal'),
            pf('-N fdns'),
            pf('-N fobjects'),
            pf('-N fglobal'),
            pf('-N fdrop'),
            pf('-N ftoexternalonly'),

            pf('-N inospoof'),
            pf('-N inointernal'),
            pf('-N iexternalmodules'),
            pf('-N iexternal'),
            pf('-N inoexternal'),
            pf('-N imodules'),
            pf('-N iintservs'),
            pf('-N iglobal'),
            pf('-N idrop'),

            pf('-N drop'),

            pf('-N log'),

            pf('-N ointernal'),
            pf('-N omodules'),
            pf('-N oglobal'),
            pf('-N odrop'),

            pf('-t nat -A PREROUTING -j premodules'),

            pf('-t nat -A POSTROUTING -j postmodules'),

            pf('-A FORWARD -j fnospoof'),
            pf('-A FORWARD -j fredirects'),
            pf('-A FORWARD -j fmodules'),
            pf('-A FORWARD -j ffwdrules'),
            pf('-A FORWARD -j fnoexternal'),
            pf('-A FORWARD -j fdns'),
            pf('-A FORWARD -j fobjects'),
            pf('-A FORWARD -j fglobal'),
            pf('-A FORWARD -j fdrop'),

            pf('-A INPUT -j inospoof'),
            pf('-A INPUT -j iexternalmodules'),
            pf('-A INPUT -j iexternal'),
            pf('-A INPUT -j inoexternal'),
            pf('-A INPUT -j imodules'),
            pf('-A INPUT -j iintservs'),
            pf('-A INPUT -j iglobal'),
            pf('-A INPUT -j idrop'),

            pf('-A OUTPUT -j ointernal'),
            pf('-A OUTPUT -j omodules'),
            pf('-A OUTPUT -j oglobal'),
            pf('-A OUTPUT -j odrop'),

            pf("-A idrop -j drop"),
            pf("-A odrop -j drop"),
            pf("-A fdrop -j drop"),
            );
    return \@commands;
}

# Method: _setDNS
#
#       Set DNS traffic for forwarding and output with destination dns
#
# Parameters:
#
#       dns - address/[mask] destination to accept DNS traffic
#
sub _setDNS # (dns)
{
    my $self = shift;
    my $dns = shift;
    my @commands = (
            pf("-A ointernal $new -p udp --dport 53 -d $dns -j ACCEPT"),
            pf("-A fdns $new -p udp --dport 53 -d $dns -j ACCEPT"),
            );
    return \@commands;
}

# Method: _setDHCP
#
#       Set output DHCP traffic 
#
# Parameters:
#
#       interface - 
#
sub _setDHCP
{
    my ($self, $interface) = @_;
    return [ pf("-A ointernal $new -o $interface -p udp --dport 67 -j ACCEPT") ];
}

# Method: _setRemoteServices
#
#       Set output rules required to remote services to work
#
#
sub _setRemoteServices
{
    my ($self) = @_;

    my @commands;

    my $gl = EBox::Global->getInstance();
    if ( $gl->modExists('remoteservices') ) {
        my $rsMod = $gl->modInstance('remoteservices');
        if ( $rsMod->eBoxSubscribed() ) {
            my $vpnIface = $rsMod->ifaceVPN();
            push(@commands,
                pf("-A ointernal $new -o $vpnIface -j ACCEPT")
            );
            try {
                my %vpnSettings = %{$rsMod->vpnSettings()};
                push(@commands,
                     pf("-A ointernal $new -p $vpnSettings{protocol} "
                          . "-d $vpnSettings{ipAddr} --dport $vpnSettings{port} -j ACCEPT")
            );
            } catch EBox::Exceptions::External with {
                # Cannot contact eBox CC
                my ($exc) = @_;
                EBox::error("Cannot contact eBox Control Center: $exc");
            };
            # Allow communications between ns and www
            eval "use EBox::RemoteServices::Configuration";
            my ($dnsServer, $publicWebServer, $mirrorCount) = (
                EBox::RemoteServices::Configuration->DNSServer(),
                EBox::RemoteServices::Configuration->PublicWebServer(),
                EBox::RemoteServices::Configuration->eBoxServicesMirrorCount(),
               );
            # We are assuming just one name server
            push(@commands,
                pf("-A ointernal $new -p udp -d $dnsServer --dport 53 -j ACCEPT")
            );
            # Public WWW servers to connect to
            for my $no ( 1 .. $mirrorCount ) {
                my $site = $publicWebServer;
                $site =~ s:\.:$no.:;
                push(@commands,
                    pf("-A ointernal $new -p tcp -d $site --dport 443 -j ACCEPT")
                );
            }
        }
    }
    return \@commands;
}

# Method: _nospoof
#
#       Set no IP spoofing (forged) for the given addresses to the
#       interface given
#
# Parameters:
#
# interface - the allowed interface for the addresses 
# addresses - An array ref with the address to allow traffic from
#             the given interface. Each slot has the following
#             fields:
#                - address - the IP address
#                - netmask - the IP network mask

sub _nospoof # (interface, \@addresses)
{
    my $self = shift;
    my ($iface, $addresses) = @_;
    my @commands;
    foreach (@{$addresses}) {
        my $addr = $_->{address};
        my $mask = $_->{netmask};
        push(@commands,
                pf("-A fnospoof -s $addr/$mask -i ! $iface -j fdrop"),
                pf("-A inospoof -s $addr/$mask -i ! $iface -j idrop"),
                pf("-A inospoof -i ! $iface -d $addr -j idrop"),
            );
    }
    return \@commands;
}

# Method: _localRedirects
#
#       Do effective local redirections. Done via
#       <EBox::Firewall::addLocalRedirect> using NAT.
#
sub _localRedirects
{
    my $self = shift;
    my $redirects = $self->{firewall}->localRedirects();
    my @commands;
    foreach my $redir (@{$redirects}) {
        my $service = $redir->{service};
        my $protocol = $self->{firewall}->serviceProtocol($service);
        my $dport = $self->{firewall}->servicePort($service);
        my $eport = $redir->{port};
        my @ifaces = @{$self->{net}->InternalIfaces()};
        foreach my $ifc (@ifaces) {
            my $addr = $self->{net}->ifaceAddress($ifc);
            (defined($addr) && $addr ne "") or next;
            push(@commands,
                    pf("-t nat -A PREROUTING -i $ifc -p $protocol ".
                        "-d ! $addr --dport $eport " .
                        "-j REDIRECT --to-ports $dport")
                );
        }
    }
    return \@commands;
}

# Method: stop
#
#       Stop iptables service, stop forwarding from kernel
#       and free all tables
#
sub stop
{
    my $self = shift;
    my @commands;
    push(@commands, @{_stopIPForward()});
    push(@commands, @{$self->_clearTables("ACCEPT")});
    root(@commands);
}

# Method: vifaceRealname
#
#       Return the real name from a virtual interface
#
# Parameters:
#
#       viface - Virtual interface
#
# Returns:
#
#       string - The real name from the given virtual interface
#
sub vifaceRealname # (viface)
{
    my $virtual = shift;
    $virtual =~ s/:.*$//;
    return $virtual;
}

# Method: start
#
#       Start firewall service setting up the structure and the rules
#       to work with iptables.
#
sub start
{
    my $self = shift;

    my @commands;

    push(@commands, @{$self->_loadIptModules()});

    push(@commands, @{$self->_setStructure()});

    my @dns = @{$self->{net}->nameservers()};
    foreach (@dns) {
        push(@commands, @{$self->_setDNS($_)});
    }

    foreach my $object (@{$self->{objects}->objects}) {
        my $members = $self->{objects}->objectMembers($object->{id});
        foreach my $member (@{$members}) {
            my $mac = $member->{macaddr};
            defined($mac) or next;
            ($mac ne "") or next;
            my $address = $member->{ipaddr};
            push(@commands,
                    pf("-A inospoof -m mac -s $address " .
                        "--mac-source ! $mac -j idrop"),
                    pf("-A fnospoof -m mac -s $address " .
                        "--mac-source ! $mac -j fdrop"),
                );
        }
    }

    my @ifaces = @{$self->{net}->ifaces()};
    foreach my $ifc (@ifaces) {
        my $addrs = $self->{net}->ifaceAddresses($ifc);
        push(@commands, @{$self->_nospoof($ifc, $addrs)});
        if ($self->{net}->ifaceMethod($ifc) eq 'dhcp') {
            push(@commands, @{$self->_setDHCP($ifc)});;
            my $dnsSrvs = $self->{net}->DHCPNameservers($ifc);
            foreach my $srv (@{$dnsSrvs}) {
                push(@commands, @{$self->_setDNS($srv)});
            }
        }
    }

    push(@commands, @{$self->_setRemoteServices()});

    push(@commands, @{$self->_redirects()});

    @ifaces = @{$self->{net}->ExternalIfaces()};
    foreach my $if (@ifaces) {
        push(@commands,
                pf("-A fnoexternal $new -i $if -j fdrop"),
                pf("-A inoexternal $new -i $if -j idrop"),
                pf("-A ftoexternalonly -o $if -j ACCEPT"),
            );

        next unless (_natEnabled());

        if ($self->{net}->ifaceMethod($if) eq 'static') {
            my $addr = $self->{net}->ifaceAddress($if);
            push(@commands,
                    pf("-t nat -A POSTROUTING -s ! $addr -o $if " .
                        "-j SNAT --to $addr")
                );
        } elsif ($self->{net}->ifaceMethod($if) eq 'dhcp') {
            push(@commands,
                    pf("-t nat -A POSTROUTING -o $if -j MASQUERADE")
                );
        }
    }

    push(@commands, @{$self->_drop()});

    push(@commands, @{$self->_log()});

    push(@commands, @{$self->_iexternal()});

    push(@commands, @{$self->_iglobal()});

    push(@commands, pf("-A ftoexternalonly -j fdrop"));

    my $rules = $self->{firewall}->OutputRules();
    foreach my $rule (@{$rules}) {
        defined($rule) or next;
        my $port = $rule->{port};
        my $proto = $rule->{protocol};
        push(@commands,
                pf("-A ointernal $new  -p $proto --dport $port -j ACCEPT")
            );
    }

    push(@commands, @{$self->_fglobal()});

    push(@commands, @{$self->_ffwdrules()});

    push(@commands, @{$self->_oglobal()});

    push(@commands, @{$self->_localRedirects()});

    push(@commands, @{_startIPForward()});

    my $global = EBox::Global->getInstance();
    my @modNames = @{$global->modNames}; 
    my @mods = @{$global->modInstancesOfType('EBox::FirewallObserver')};
    my @modRules;
    foreach my $mod (@mods) {
        my $helper = $mod->firewallHelper();
        ($helper) or next;
        # push chain creation directly to commands so they take precedence
        push(@commands, map { pf("-N $_") } @{$helper->chains()});
        push(@modRules,
                @{$self->_doRuleset('nat', 'premodules', $helper->prerouting())}
            );
        push(@modRules,
                @{$self->_doRuleset('nat', 'postmodules', $helper->postrouting())}
            );
        push(@modRules,
                @{$self->_doRuleset('filter', 'fmodules', $helper->forward())}
            );
        push(@modRules,
                @{$self->_doRuleset('filter', 'iexternalmodules', $helper->externalInput())}
            );
        push(@modRules,
                @{$self->_doRuleset('filter', 'imodules', $helper->input())}
            );
        push(@modRules,
                @{$self->_doRuleset('filter', 'omodules', $helper->output())}
            );
    }
    my @sortedRules = sort { $a->{'priority'} <=> $b->{'priority'} } @modRules;
    push(@commands, map { pf($_->{'rule'}) } @sortedRules);
    root(@commands);
}

sub _loadIptModules
{
    my @commands;
    foreach my $module (IPT_MODULES) {
        push(@commands, "modprobe $module || true");
    }
    return \@commands;
}

sub _doRuleset # (table, chain, \@rules)
{
    my ($self, $table, $chain, $rules) = @_;

    my @commands;
    foreach my $r (@{$rules}) {
        my $priority = 50;
        my $pfrule;
        my $pfchain = $chain;
        if (ref($r) eq 'HASH') {
            if(defined($r->{'priority'})) {
                $priority = $r->{'priority'};
            }
            if(defined($r->{'chain'})) {
                $pfchain = $r->{'chain'};
            }
            $pfrule = $r->{'rule'};
        } else {
            $pfrule = $r;
        }
        $pfrule = "-t $table -A $pfchain $pfrule";
        my $r = { 'priority' => $priority, 'rule' => $pfrule };
        push(@commands, $r);
    }
    return \@commands;
}

# Method: _iexternalCheckInit
#
# 	Add checks to iexternalmodules and iexternal to only affect
# 	packates coming from external interfaces
sub _iexternalCheckInit
{
    my ($self) = @_;

    my @commands;

    my @internalIfaces = @{$self->{net}->InternalIfaces()};
    foreach my $if (@internalIfaces) {
        push(@commands,
            pf("-A iexternalmodules -i $if -j RETURN"),
            pf("-A iexternal -i $if -j RETURN"),
        );
    }
    return \@commands;
}

# Method: _iexternal
#
# Add checks to iexternalmodules and iexternal to only affect
# packates coming from external interfaces
sub _iexternal
{
    my ($self) = @_;

    my @commands;

    push (@commands, @{$self->_iexternalCheckInit()});
    my $iptHelper = new EBox::Firewall::IptablesHelper;
    for my $rule (@{$iptHelper->ExternalToEBoxRuleTable()}) {
        push(@commands, pf("$rule"));
    }
    return \@commands;
}

# Method: _iglobal
#
#	Add rules to iglobal, that is the chain to control access
#	from the internal networks to eBox
sub _iglobal
{
    my ($self) = @_;

    my @commands;

    my $iptHelper = new EBox::Firewall::IptablesHelper;
    for my $rule (@{$iptHelper->InternalToEBoxRuleTable()}) {
        push(@commands, pf("$rule"));
    }
    return \@commands;
}

# Method: _oglobal
#
#   Add rules to iglobal, that is the chain to control access
#   from eBox to external services
sub _oglobal
{
    my ($self) = @_;

    my @commands;

    my $iptHelper = new EBox::Firewall::IptablesHelper;
    for my $rule (@{$iptHelper->EBoxOutputRuleTable()}) {
        push(@commands, pf("$rule"));
    }
    return \@commands;
}


# Method: _fglobal
#
#   Add rules to fglobal, that is the chain to control access
#   from the internal networks to Internet
sub _fglobal
{
    my ($self) = @_;

    my @commands;

    my $iptHelper = new EBox::Firewall::IptablesHelper;
    for my $rule (@{$iptHelper->ToInternetRuleTable()}) {
        push(@commands, pf("$rule"));
    }
    return \@commands;
}

# Method: _ffwdrules
#
#   Add rules to ffwdrules, that is the chain to control access
#   from the external networks to Internet
sub _ffwdrules
{
    my ($self) = @_;

    my @commands;

    my @internalIfaces = @{$self->{net}->InternalIfaces()};
    foreach my $if (@internalIfaces) {
        push(@commands, pf("-A ffwdrules -i $if -j RETURN"));
    }
    my $iptHelper = new EBox::Firewall::IptablesHelper;
    for my $rule (@{$iptHelper->ExternalToInternalRuleTable()}) {
        push(@commands, pf("$rule"));
    }
    return \@commands;
}

# Method: _redirects
#
#	Add redirects rules
sub _redirects
{
    my ($self) = @_;

    my @commands;

    my $iptHelper = new EBox::Firewall::IptablesHelper;
    for my $rule (@{$iptHelper->RedirectsRuleTable()}) {
        push(@commands, pf("$rule"));
    }
    return \@commands;
}

# Method: _drop
#
#	Set up drop chain. Log rule and drop rule
#	
sub _drop
{
    my ($self) = @_;

    my @commands;
    push(@commands, pf('-I drop -j DROP'));

    # If logging is disabled we are done
    if($self->{firewall}->logging()) {

        my $limit = EBox::Config::configkey('iptables_log_limit');
        my $burst = EBox::Config::configkey('iptables_log_burst');

        unless (defined($limit) and $limit =~ /^\d+$/) {
        throw EBox::Exceptions::External(__('You must set the ' .
            'iptables_log_limit variable in the ebox configuration file'));

        }

        unless (defined($burst) and $burst =~ /^\d+$/) {
        throw EBox::Exceptions::External(__('You must set the ' .
            'iptables_log_burst variable in the ebox configuration file'));

        }
        push(@commands,
            pf("-I drop -j LOG -m limit --limit $limit/min " .
            "--limit-burst $burst" . 
            ' --log-level ' . SYSLOG_LEVEL . 
            ' --log-prefix "ebox-firewall drop "')
        );
    }
    return \@commands;
}

# Method: _log
#
#	Set up log chain. Log rule and return rule
#
sub _log
{
    my ($self) = @_;

    my @commands;
    push(@commands, pf('-I log -j RETURN'));

    # If logging is disabled we are done
    if ($self->{firewall}->logging()) {
        my $limit = EBox::Config::configkey('iptables_log_limit');
        my $burst = EBox::Config::configkey('iptables_log_burst');

        unless (defined($limit) and $limit =~ /^\d+$/) {
        throw EBox::Exceptions::External(__('You must set the ' .
            'iptables_log_limit variable in the ebox configuration file'));

        }

        unless (defined($burst) and $burst =~ /^\d+$/) {
        throw EBox::Exceptions::External(__('You must set the ' .
            'iptables_log_burst variable in the ebox configuration file'));

        }
        push(@commands,
            pf("-I log -j LOG -m limit --limit $limit/min " .
            "--limit-burst $burst" . 
            ' --log-level ' . SYSLOG_LEVEL . 
            ' --log-prefix "ebox-firewall log "')
        );
    }
    return \@commands;
}

# Method: _natEnabled
#
#   Fetch value to enable NAT
#
sub _natEnabled
{
    my $nat =  EBox::Config::configkey('nat_enabled');

    return 1 unless (defined($nat));

    if ($nat =~ /no/) {
        return undef;
    } else {
        return 1;
    }
}

1;
