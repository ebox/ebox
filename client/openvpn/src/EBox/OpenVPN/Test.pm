package EBox::OpenVPN::Test;
use base 'EBox::Test::Class';
# Description:
use strict;
use warnings;


# BEGIN {
#   use EBox::NetWrappers::TestStub;
#   EBox::NetWrappers::TestStub::setFakeIfaces( {
# 					       eth0 => { up => 1, address => { '192.168.0.100' => '255.255.255.0' } },
# 					       ppp0 => { up => 1, address => { '192.168.45.233' => '255.255.255.0' } },
# 					       eth1 => {up  => 1, address => { '192.168.0.233' => '255.255.255.0' }},
# 					    } );
# }

use Test::More;
use Test::Exception;
use Test::Differences;
use EBox::Global;
use EBox::Test qw(checkModuleInstantiation);

use Perl6::Junction qw(all);

use EBox::NetWrappers::TestStub;

use lib '../..';

sub testDir
{
    return  '/tmp/ebox.openvpn.test';
}


sub _confDir
{
    my ($self) = @_;
    return $self->testDir . '/conf';
}

sub _moduleInstantiationTest : Test
{
    checkModuleInstantiation('openvpn', 'EBox::OpenVPN');
}

sub setUpConfiguration : Test(setup)
{
    my ($self) = @_;
   
    my @config = (
		  '/ebox/modules/openvpn/active'  => 1,
		  '/ebox/modules/openvpn/openvpn_bin'  => '/usr/sbin/openvpn',
		  '/ebox/modules/openvpn/user'  => 'nobody',
		  '/ebox/modules/openvpn/group' => 'nobody',
		  '/ebox/modules/openvpn/conf_dir' => $self->_confDir(),
		  );

    EBox::GConfModule::TestStub::setConfig(@config);
    EBox::Global::TestStub::setEBoxModule('openvpn' => 'EBox::OpenVPN');

}


sub clearConfiguration : Test(teardown)
{
    EBox::GConfModule::TestStub::setConfig();
}


sub newAndRemoveServerTest  : Test(24)
{
    my $openVPN = EBox::OpenVPN->_create();

    my @serversNames = qw(server1 sales staff_vpn );
    my %serversParams = (
			 server1 => [subnet => '10.8.0.0', subnetNetmask => '255.255.255.0', port => 3000, proto => 'tcp', caCertificate => '/etc/cert/ca.cert', serverCertificate => '/etc/cert/server.cert', serverKey => '/etc/cert/server.key', type => 'one2many'],
			 sales => [subnet => '10.8.0.0', subnetNetmask => '255.255.255.0', port => 3001, proto => 'tcp', caCertificate => '/etc/cert/ca.cert', serverCertificate => '/etc/cert/server.cert', serverKey => '/etc/cert/server.key', type => 'one2many'],
			 staff_vpn => [subnet => '10.8.0.0', subnetNetmask => '255.255.255.0', port => 3002, proto => 'tcp', caCertificate => '/etc/cert/ca.cert', serverCertificate => '/etc/cert/server.cert', serverKey => '/etc/cert/server.key', type => 'one2many'],

			 );

    dies_ok { $openVPN->removeServer($serversNames[0]) } "Checking that removal of server when the server list is empty raises error";
    dies_ok {  $openVPN->newServer('incorrect-dot', $serversParams{server1})  } 'Testing addition of incorrect named server';

    foreach my $name (@serversNames) {
	my $instance;
	my @params = @{ $serversParams{$name} };
	lives_ok { $instance = $openVPN->newServer($name, @params)  } 'Testing addition of new server';
	isa_ok $instance, 'EBox::OpenVPN::Server', 'Checking that newServer has returned a server instance';
	dies_ok { $instance  = $openVPN->newServer($name, @params)  } 'Checking that the servers cannot be added a second time';
    }

    my @actualServersNames = $openVPN->serversNames();
    eq_or_diff [sort @actualServersNames], [sort @serversNames], "Checking returned test names";

    # removal cases..
 
	
    foreach my $name (@serversNames) {
	my $instance;
	lives_ok { $instance = $openVPN->removeServer($name)  } 'Testing server removal';
	dies_ok  { $openVPN->server($name) } 'Testing that can not get the server object that represents the deleted server ';

	my @actualServersNames = $openVPN->serversNames();
	ok $name ne all(@actualServersNames), "Checking that deleted servers name does not appear longer in serves names list";
    
	dies_ok { $instance = $openVPN->removeServer($name)  } 'Testing that a deleted server can not be deleted agian';
    }
}


sub usesPortTest : Test(16)
{
  my ($self) = @_;

  fakeInterfaces();

  # add servers to openvpn (we add only the attr we care for in this testcase
  my @config = (
		  '/ebox/modules/openvpn/active'  => 1,
		  '/ebox/modules/openvpn/openvpn_bin'  => '/usr/sbin/openvpn',
		  '/ebox/modules/openvpn/user'  => 'nobody',
		  '/ebox/modules/openvpn/group' => 'nobody',
		  '/ebox/modules/openvpn/conf_dir' => $self->_confDir(),

		  '/ebox/modules/openvpn/server/macaco/active'    => 1,
		  '/ebox/modules/openvpn/server/macaco/port'    => 1194,
		  '/ebox/modules/openvpn/server/macaco/proto'   => 'tcp',

		  '/ebox/modules/openvpn/server/mandril/active'    => 1,
		  '/ebox/modules/openvpn/server/mandril/port'    => 1200,
		  '/ebox/modules/openvpn/server/mandril/proto'   => 'tcp',
		  '/ebox/modules/openvpn/server/mandril/local'   => '192.168.45.233',

		  '/ebox/modules/openvpn/server/gibon/active'    => 1,
		  '/ebox/modules/openvpn/server/gibon/port'   => 1294,
		  '/ebox/modules/openvpn/server/gibon/proto'  => 'udp',
		      );
  EBox::GConfModule::TestStub::setConfig(@config);
  
  my $openVPN = EBox::OpenVPN->_create();

  # regular cases
  ok $openVPN->usesPort('tcp', 43, 'tun0'), "Checking that tun interface is reported as used";
   ok $openVPN->usesPort('tcp', 1194), "Checking if a used port is correctly reported";
  ok $openVPN->usesPort('tcp', 1194, 'ppp0'), "Checking if a used port is correctly reported";
  ok $openVPN->usesPort('tcp', 1194, 'eth0'), "Checking if a used port is correctly reported";
  ok $openVPN->usesPort('tcp', 1194, 'eth1'), "Checking if a used port is correctly reported";

  # protocol awareness
  ok !$openVPN->usesPort('udp', 1194);
  ok $openVPN->usesPort('udp', 1294);
  ok !$openVPN->usesPort('tcp', 1294);

  # local address case
  ok $openVPN->usesPort('tcp', 1200), "Checking if a used port in only one interface is correctly reported";
  ok $openVPN->usesPort('tcp', 1200, 'ppp0'), "Checking if a used port in only one interface is correctly reported";
  ok !$openVPN->usesPort('tcp', 1200, 'eth0'), "Checking if a used port in only one interface does not report as used in another interface";

   # unused ports case
  ok !$openVPN->usesPort('tcp', 1800), "Checking if a unused prot is correctly reported";
  ok !$openVPN->usesPort('tcp', 1800, 'eth0'), "Checking if a unused port is correctly reported";
  ok !$openVPN->usesPort('tcp', 1800), "Checking if a unused port is correctly reported";

  # server inactive case
  EBox::GConfModule::TestStub::setEntry( '/ebox/modules/openvpn/server/macaco/active'    => 0);
  ok !$openVPN->usesPort('tcp', 1194), "Checking that usesPort does not report  any port for inactive servers";

  # openvpn inacitve case
  EBox::GConfModule::TestStub::setEntry( '/ebox/modules/openvpn/active'    => 0);
  ok !$openVPN->usesPort('tcp', 1194), "Checking that usesPort does not report  any port for a inactive OpenVPN module";
}




sub fakeInterfaces
{
  # set fake interfaces
  EBox::NetWrappers::TestStub::setFakeIfaces( {
					       eth0 => { up => 1, address => { '192.168.0.100' => '255.255.255.0' } },
					       ppp0 => { up => 1, address => { '192.168.45.233' => '255.255.255.0' } },
					       eth1 => {up  => 1, address => { '192.168.0.233' => '255.255.255.0' }},
					    } );
}

1;
