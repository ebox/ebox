package EBox::OpenVPN::FirewallHelper;
use base 'EBox::FirewallHelper';
# Description:
use strict;
use warnings;


sub new 
{
        my ($class, %opts) = @_;

        my $self = $class->SUPER::new(%opts);
	$self->{ifaces}           =  delete $opts{ifaces};
	$self->{portsByProto}     =  delete $opts{portsByProto};
	$self->{serversToConnect} =  delete $opts{serversToConnect};

        bless($self, $class);
        return $self;
}



sub ifaces
{
    my ($self) = @_;
    return $self->{ifaces};
}

sub portsByProto
{
    my ($self) = @_;
    return $self->{portsByProto};
}

sub serversToConnect
{
    my ($self) = @_;
    return $self->{serversToConnect};
}

sub input
{
    my ($self) = @_;
    my @rules;

    # do not firewall openvpn virtual ifaces
    foreach my $iface (@{ $self->ifaces() }) {
      push @rules, "-i $iface -j ACCEPT";
    }

    my $portsByProto = $self->portsByProto;
    foreach my $proto (keys %{$portsByProto}) {
	my @ports = @{ $portsByProto->{$proto} };
	foreach my $port (@ports) {
	    my $rule = "--protocol $proto --destination-port $port -j ACCEPT";
	    push @rules, $rule;
	}
    }


    return \@rules;
}

sub output
{
    my ($self) = @_;
    my @rules;

    # do not firewall openvpn virtual ifaces
    foreach my $iface (@{ $self->ifaces() }) {
      push @rules, "-o $iface -j ACCEPT";
    }
    
    foreach my $server_r (@{ $self->serversToConnect() }) {
      my ($serverProto, $server, $serverPort) = @{ $server_r };
      my $connectRule =  "--protocol $serverProto --destination $server --destination-port $serverPort -j ACCEPT";
      push @rules, $connectRule;
    }



    return \@rules;
}


sub forward
{
    my ($self) = @_;
    my @rules;

    # do not firewall openvpn virtual ifaces
    foreach my $iface (@{ $self->ifaces() }) {
      push @rules, "-i $iface -j ACCEPT";
      push @rules, "-o $iface -j ACCEPT";
    }

    return \@rules;
}


1;
