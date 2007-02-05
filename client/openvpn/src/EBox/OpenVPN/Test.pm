package EBox::OpenVPN::Test;
use base 'EBox::Test::Class';
# Description:
use strict;
use warnings;



use Test::More;
use Test::Exception;
use Test::Differences;
use EBox::Global;
use EBox::Test qw(checkModuleInstantiation);
use EBox::TestStubs qw(fakeEBoxModule);

use Perl6::Junction qw(all any);

use EBox::NetWrappers::TestStub;
use EBox::CA::TestStub;

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


# XXX replace with #419 when it is done
sub ignoreChownRootCommand : Test(startup)
{
  my $root_r = EBox::Sudo->can('root');

  my $rootIgnoreChown_r = sub {
    my ($cmd) = @_;
    my ($cmdWithoutParams) = split '\s+', $cmd;
    if (($cmdWithoutParams eq 'chown') or ($cmdWithoutParams eq '/bin/chown')) {
      return [];  
    }

    return $root_r->($cmd);
  };


  defined $root_r or die 'Can not get root sub from EBox::Sudo';

  Test::MockObject->fake_module(
				'EBox::Sudo',
				root => $rootIgnoreChown_r,
			       )
}



sub fakeNetworkModule
{
  my ($externalIfaces_r, $internalIfaces_r) = @_;

  my @externalIfaces = defined $externalIfaces_r ? @{ $externalIfaces_r } :  qw(eth0 eth2);
  my @internalIfaces = defined $internalIfaces_r ? @{ $internalIfaces_r } : ('eth1', 'eth3');

  my $anyExternalIfaces = any(@externalIfaces);
  my $anyInternalIfaces = any(@internalIfaces);

  my $ifaceExistsSub_r = sub {
    my ($self, $iface) = @_;
    return ($iface eq $anyInternalIfaces) or ($iface eq $anyExternalIfaces);
  };

  my $ifaceIsExternalSub_r = sub {
    my ($self, $iface) = @_;
    return  ($iface eq $anyExternalIfaces);
  };



  fakeEBoxModule(
		 name => 'network',
		 package => 'EBox::Network',
		 subs => [
			  ifaceIsExternal => $ifaceIsExternalSub_r,
			  ifaceExists     => $ifaceExistsSub_r,
			  ExternalIfaces  => sub { return \@externalIfaces },
			  InternalIfaces  => sub { return \@internalIfaces },
			  ifaceMethod     => sub { return 'anythingButNonSet' }, # this if for bug #395
			 ],
		);

}


sub fakeCA : Test(startup)
{
  EBox::CA::TestStub::fake();
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
    EBox::Global::TestStub::setEBoxModule('ca' => 'EBox::CA');

    fakeInterfaces();
}


sub clearConfiguration : Test(teardown)
{
    EBox::GConfModule::TestStub::setConfig();
}



sub newAndRemoveClientTest : Test(15)
{
  my $openVPN = EBox::OpenVPN->_create();
 
  my @mockCertFiles = qw(/tmp/ca.pem /tmp/client.pem /tmp/client.key);
  system "touch @mockCertFiles";
  ($? == 0) or die "Can not  create mock certification files in /tmp: $!";
 
  my @clientsNames = qw(client1 client2);
  my %clientsParams = (
		       client1 =>  [ 
				    proto => 'tcp',
				    caCertificatePath => '/tmp/ca.pem',
				    certificatePath   => '/tmp/client.pem',
				    certificateKey    => '/tmp/client.key',
				    servers           => [
							  ['192.168.55.21' => 1040],
							 ],
				    service           => 1,
				   ],

		       client2 =>  [ 
				    proto => 'tcp',
				    caCertificatePath => '/tmp/ca.pem',
				    certificatePath   => '/tmp/client.pem',
				    certificateKey    => '/tmp/client.key',
				    servers           => [
							  ['192.168.55.21' => 1040],
							  ['192.168.55.23' => 1041],
							 ],
				    service           => 1,
				   ],
		      );

    foreach my $name (@clientsNames) {
	my $instance;
	my @params = @{ $clientsParams{$name} };
	lives_ok { $instance = $openVPN->newClient($name, @params)  } 'Testing addition of new client';
	isa_ok $instance, 'EBox::OpenVPN::Client', 'Checking that newClient has returned a client instance';
	dies_ok { $instance  = $openVPN->newClient($name, @params)  } 'Checking that the clients cannot be added a second time';
    }

    my @actualClientsNames = $openVPN->clientsNames();
    eq_or_diff [sort @actualClientsNames], [sort @clientsNames], "Checking returned test names";

    # removal cases..
 
	
    foreach my $name (@clientsNames) {
	my $instance;
	lives_ok { $instance = $openVPN->removeClient($name)  } 'Testing client removal';
	dies_ok  { $openVPN->client($name) } 'Testing that can not get the client object that represents the deleted client ';

	my @actualClientsNames = $openVPN->clientsNames();
	ok $name ne all(@actualClientsNames), "Checking that deleted clients name does not appear longer in serves names list";
    
	dies_ok { $instance = $openVPN->removeClient($name)  } 'Testing that a deleted client can not be deleted agian';
    }
  
  system "rm @mockCertFiles";
  ($? == 0) or die "Can not  remove mock certification files in /tmp: $!";
}

sub newAndRemoveServerTest  : Test(24)
{

  my $ca = EBox::Global->modInstance('ca');
  my @fakeCertificates = (
			  {
			   dn => 'CN=monos',
			   isCACert => 1,
			  },
			  {
			   dn => "CN=serverCertificate",
			   path => 'certificate.crt',
			   keys => [qw(certificate.pub certificate.key)],
			  },
			 );
  $ca->setInitialState(\@fakeCertificates);


  my $openVPN = EBox::OpenVPN->_create();
  
  my @serversNames = qw(server1 sales staff_vpn );
  my %serversParams = (
			 server1 => [service => 1, subnet => '10.8.0.0', subnetNetmask => '255.255.255.0', port => 3000, proto => 'tcp',  certificate => 'serverCertificate',  type => 'one2many'],
			 sales => [service => 0, subnet => '10.8.0.0', subnetNetmask => '255.255.255.0', port => 3001, proto => 'tcp',  certificate => 'serverCertificate',  type => 'one2many'],
			 staff_vpn => [service => 1, subnet => '10.8.0.0', subnetNetmask => '255.255.255.0', port => 3002, proto => 'tcp',  certificate => 'serverCertificate',  type => 'one2many'],

			 );

    dies_ok { $openVPN->removeServer($serversNames[0]) } "Checking that removal of server when the server list is empty raises error";
    dies_ok {  $openVPN->newServer('incorrect-dot', @{ $serversParams{server1} })  } 'Testing addition of incorrect named server';

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

  # openvpn inactive case
  EBox::GConfModule::TestStub::setEntry( '/ebox/modules/openvpn/active'    => 0);
  ok !$openVPN->usesPort('tcp', 1194), "Checking that usesPort does not report  any port for a inactive OpenVPN module";
}

sub setServiceTest : Tests(5)
{
  my $ca = EBox::Global->modInstance('ca');
  $ca->destroyCA();
  # the test begins with inactive service and no CA created
  EBox::TestStubs::setConfigKey( '/ebox/modules/openvpn/active'  => 0,);
  my $openVPN = EBox::OpenVPN->_create();

  dies_ok { $openVPN->setService(1)  } 'Checking if enabling server without Certification authority in place raises error';

  # create CA

  my @fakeCertificates = (
			  {
			   dn => 'CN=monos',
			   isCACert => 1,
			  },
			 );
  $ca->setInitialState(\@fakeCertificates);

  foreach my $serviceExpected (0, 1, 1, 0,) {
    my $oldService = $openVPN->service();
    lives_and( 
	      sub { 
		$openVPN->setService($serviceExpected);
		is $openVPN->service, $serviceExpected;
	      },  
	      "Checking if OpenVPN service is correctly changed from $oldService to $serviceExpected")
  }
}



sub fakeInterfaces
{
  # set fake interfaces
  EBox::NetWrappers::TestStub::fake();
  EBox::NetWrappers::TestStub::setFakeIfaces( {
					       eth0 => { up => 1, address => { '192.168.0.100' => '255.255.255.0' } },
					       ppp0 => { up => 1, address => { '192.168.45.233' => '255.255.255.0' } },
					       eth1 => {up  => 1, address => { '192.168.0.233' => '255.255.255.0' }},
					    } );

  # fake network module..
  my @externalIfaces = qw(eth0 ppp0 eth1);
  my @internalIfaces = ();

  my $anyExternalIfaces = any(@externalIfaces);
  my $anyInternalIfaces = any(@internalIfaces);

  my $ifaceExistsSub_r = sub {
    my ($self, $iface) = @_;
    return ($iface eq $anyInternalIfaces) or ($iface eq $anyExternalIfaces);
  };

  my $ifaceIsExternalSub_r = sub {
    my ($self, $iface) = @_;
    return  ($iface eq $anyExternalIfaces);
  };


  fakeEBoxModule(
		 name => 'network',
		 package => 'EBox::Network',
		 subs => [
			  ifaceIsExternal => $ifaceIsExternalSub_r,
			  ifaceExists     => $ifaceExistsSub_r,
			  ExternalIfaces  => sub { return \@externalIfaces },
			  InternalIfaces  => sub { return \@internalIfaces },
			 ],
		);

}




1;
