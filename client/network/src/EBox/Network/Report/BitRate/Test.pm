package EBox::Network::Report::BitRate::Test;
use base 'EBox::Test::Class';
#
use strict;
use warnings;


use Test::Exception;
use Test::MockObject;
use Test::More;

use lib '../../../..';

use EBox::Network::Report::BitRate;

my %bpsByRRD;

sub _fakeAddBpsToRRD : Test(startup)
{
  my $fakeSub_r = sub {
    my ($rrd, $bps) = @_;
    $bpsByRRD{$rrd} += $bps;
  };

  Test::MockObject->fake_module(
				'EBox::Network::Report::BitRate',
				_addBpsToRRD => $fakeSub_r,
			       );
}





sub addBpsTest : Test(4)
{
  my %expectedRRDs;

  my $wwwPort = 80;
  my $wwwRRD  =  EBox::Network::Report::BitRate::serviceRRD('www');
  my $sshPort = 22; 
  my $sshRRD  =  EBox::Network::Report::BitRate::serviceRRD('ssh'); 

  my $src1    = '192.168.45.3';
  my $src1RRD = EBox::Network::Report::BitRate::srcRRD($src1);
  my $src2    = '10.45.23.12';
  my $src2RRD = EBox::Network::Report::BitRate::srcRRD($src2);
  
  my $src1WwwRRD = EBox::Network::Report::BitRate::srcAndServiceRRD($src1, 'www');
  my $src2WwwRRD = EBox::Network::Report::BitRate::srcAndServiceRRD($src2, 'www');
  my $src1SshRRD = EBox::Network::Report::BitRate::srcAndServiceRRD($src1, 'ssh');
  my $src2SshRRD = EBox::Network::Report::BitRate::srcAndServiceRRD($src2, 'ssh');



  EBox::Network::Report::BitRate::addBps(
					 proto => 'tcp',
					 src   => $src1,
					 sport => 10000,
					 dst   => '45.23.12.12',
					 dport => $wwwPort,
					 bps => 1,
					); 

  

  $expectedRRDs{$src1RRD} +=  1;
  $expectedRRDs{$wwwRRD} += 1;
  $expectedRRDs{$src1WwwRRD} +=  1;


  is_deeply \%bpsByRRD, {}, 'checking that before flushing the bps the RRDs have not nay data';

  EBox::Network::Report::BitRate->flushBps();

  is_deeply \%bpsByRRD, \%expectedRRDs, 'checking data after flushing the bps ';


  EBox::Network::Report::BitRate::addBps(
					 proto => 'tcp',
					 src   => $src2,
					 sport => 10000,
					 dst   => '45.23.12.12',
					 dport => $wwwPort,
					 bps => 1,
					); 
  $expectedRRDs{$src2RRD} += 1;
  $expectedRRDs{$wwwRRD}  += 1;
  $expectedRRDs{$src2WwwRRD} += 1;
  

  EBox::Network::Report::BitRate::addBps(
					 proto => 'tcp',
					 src   => $src1,
					 sport => 10000,
					 dst   => '45.23.12.12',
					 dport => $wwwPort,
					 bps => 1,
					); 

  $expectedRRDs{$src1RRD} += 1;
  $expectedRRDs{$wwwRRD}  += 1;
  $expectedRRDs{$src1WwwRRD} += 1;

  EBox::Network::Report::BitRate->flushBps();

  is_deeply \%bpsByRRD, \%expectedRRDs, 'checking data after two more adds ';

  EBox::Network::Report::BitRate::addBps(
					 proto => 'tcp',
					 src   => $src2,
					 sport => 10000,
					 dst   => '45.23.12.12',
					 dport => $sshPort,
					 bps => 2,
					); 
  $expectedRRDs{$src2RRD} += 2;
  $expectedRRDs{$sshRRD}  += 2;
  $expectedRRDs{$src2SshRRD} += 2;
  

  EBox::Network::Report::BitRate::addBps(
					 proto => 'tcp',
					 src   => $src1,
					 sport => 10000,
					 dst   => '45.23.12.12',
					 dport => $sshPort,
					 bps => 1,
					); 

  $expectedRRDs{$src1RRD} += 1;
  $expectedRRDs{$sshRRD}  += 1;
  $expectedRRDs{$src1SshRRD} += 1;
  
  EBox::Network::Report::BitRate->flushBps();

  is_deeply \%bpsByRRD, \%expectedRRDs, 'checking data after two more adds of another service';
}

1;
