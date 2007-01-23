use strict;
use warnings;
use Cwd;

use lib '../..';
use EBox::Test::Mason;

use Test::More tests => 4;

my $printOutput = 0;
my $outputFile  = '/tmp/serverProperties.html';
system "rm -rf $outputFile";

my $template =   getcwd() . '/../serverProperties.mas';
my @compRoot = ('/usr/share/ebox/templates');

my @submitParams = (
		    submitName => 'test', 
		    submitValue => 'submit test',
		   );


my @certificates = ('macaco certificate', 'baboon certificate');

my %properties = (
		   service => 1,
		   port    => 10000,
		   subnet  => '192.168.132',
		   subnetNetmask => '255.255.255.0',
		   proto         => 'tcp',
		   clientToClient => 0,
		   local          => '192.168.133.41',
		   tlsRemote      => undef,
		  );

my %propiertiesWithTlsRemote = (
		   service => 1,
		   port    => 10000,
		   subnet  => '192.168.132',
		   subnetNetmask => '255.255.255.0',
		   proto         => 'tcp',
		   clientToClient => 0,
		   local          => '192.168.133.41',
		   tlsRemote      => 'macaco certificate',
		  );


my @cases = (
	     [ @submitParams, availableCertificates => [], ],  # minimal arguments case with NO certifcates
	     [ @submitParams, availableCertificates => \@certificates, ],  # minimal arguments case with  certificates
	     [ @submitParams, availableCertificates => \@certificates, properties => \%properties],  
	     [ @submitParams, availableCertificates => \@certificates, properties => \%propiertiesWithTlsRemote],  
	    );


foreach my $params (@cases) {
  EBox::Test::Mason::checkTemplateExecution(template => $template, templateParams => $params, printOutput => $printOutput, outputFile => $outputFile, compRoot => \@compRoot);
}

1;
