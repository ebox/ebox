# Description:
use strict;
use warnings;


use Test::More 'no_plan';
use Test::Exception;

use lib '../../..';

use_ok ('EBox::CGI::Base');

use EBox::Test::CGI ':all';
use EBox::Mock;

EBox::Mock::mock();

paramsAsHashTest();
validateParamsTest();
processTest();


sub paramsAsHashTest
{
    my $cgi = new EBox::CGI::DumbCGI;
    my %params = (
		  mono    => 'macaco',
		  primate => 'gorila',
		  lemur   => 'indri',
		  numero  => 34
		  );

    setCgiParams($cgi, %params);

    my $cgiParamsHash = $cgi->paramsAsHash();

    is_deeply(\%params, $cgiParamsHash, 'Checking return value of paramsAsHash')
}

sub validateParamsTest
{
    my @correctCases = @{ cgiParametersCorrectCases() };
    my @deviantCases = @{ cgiParametersDeviantCases() };

    foreach my $case_r (@correctCases) {
	my $cgi = new EBox::CGI::DumbCGI;
	my @params = @{ $case_r };
	setCgiParams($cgi, @params);

	lives_ok { $cgi->_validateParams()  } "Checking parameters validation with correct parameters: @params";
    }

 

    foreach my $case_r (@deviantCases) {
	my $cgi = new EBox::CGI::DumbCGI;
	my @params = @{ $case_r };
	setCgiParams($cgi, @params);

	dies_ok { $cgi->_validateParams()  } "Checking parameters validation with deviant parameters: @params";
    }
}


sub processTest
{
    my @correctCases = @{ cgiParametersCorrectCases() };
    
    foreach my $case_r (@correctCases) {
	my $cgi = new EBox::CGI::DumbCGI;
	my @cgiParams = @{ $case_r };
	my @expectedMasonParametes = @cgiParams;

	lives_ok { runCgi($cgi, @cgiParams) } "Checking error-free cgi run";
	cgiErrorNotOk($cgi, 'Checking that not error has been found in the cgi');
	checkMasonParameters($cgi, wantedParameters => {@expectedMasonParametes});
    }

    my @deviantCases = (
			# first, puck up all the incorrect parameters cases
			@{ cgiParametersDeviantCases() },
			# then add forceError parameter in all parameters correct cases
			map {
			    my %case = @{$_};
			    $case{errorFound} = 1;
			    [%case]
			} @{ cgiParametersCorrectCases() },
			);

    foreach my $case_r (@deviantCases) {
	my $cgi = new EBox::CGI::DumbCGI;
	my @cgiParams = @{ $case_r };
	my @expectedMasonParametes =  (@cgiParams, errorFound => 1);

	lives_ok { runCgi($cgi, @cgiParams) } 'Checking that cgi with error does not throw any exception';
	cgiErrorOk($cgi, 'Checking that error is correctly marked');
	checkMasonParameters($cgi, wantedParameters => {@expectedMasonParametes}, testName => 'Checking mason parameters for CGI with error');
    }
    
}


sub cgiParametersCorrectCases
{

  my @requiredParams = @{ EBox::CGI::DumbCGI::requiredParameters() };
  my @optionalParams = grep  { $_ ne 'forceError'   }  @{ EBox::CGI::DumbCGI::optionalParameters() };

 my @correctCases = (
			[ map { $_ => 'req'  } @requiredParams ] ,
 			[ (map { $_ => 'req'  } @requiredParams), map { ($_ => 'opt')  } @optionalParams, ] ,
		    	[ (map { $_ => 'req'  } @requiredParams), map { $_ => 'opt'  }  (grep { $_ =~ m/[12]/ }  @optionalParams) ] ,
		        [ (map { $_ => 'req'  } @requiredParams), map { $_ => 'opt'  }  (grep { $_ =~ m/3/ }  @optionalParams) ] ,
     );

  return \@correctCases;
}


sub cgiParametersDeviantCases
{
  my @requiredParams = @{ EBox::CGI::DumbCGI::requiredParameters() };
  my @optionalParams = @{ EBox::CGI::DumbCGI::optionalParameters() };

   my @deviantCases = (
			# no parameters
			[],
			# only optional parameters
			[map { $_ => 'opt' }   @optionalParams ],
			# missing required parameters
			[ map { $_ => 'req'  } grep { m/[12]/  }  @requiredParams ] ,
			# extra parameters
			[ (map { $_ => 'req'  }  @requiredParams), 'extraParameter' => 1 ] ,
			);

  return \@deviantCases;
}

package EBox::CGI::DumbCGI;
use base 'EBox::CGI::Base';

sub new 
{
    my ($class, @params) = @_;
    my $self = $class->SUPER::new(@params);

    bless $self, $class;
    return $self;
}


sub actuate
{
    my ($self) = @_;

    my $errorParam = $self->param('forceError');


    if (defined $errorParam) {
	throw EBox::Exceptions::External $errorParam;
    }
}

sub optionalParameters
{
    return [qw(forceError optional1 optional2)];
}

sub requiredParameters
{
    return [qw(required1 required2 required3)];
}

# echoes the cgi parameters as mason parameters and adds (errorFound => 1) if cgi has any error
sub masonParameters
{
    my ($self) = @_;

    my @names = @{ $self->params() };
    my @params = map { $_ => $self->param($_) } @names; 

    my $error    = $self->{error};
    my $oldError = $self->{olderror};

    if (defined $error  or (defined $oldError)) {
	push @params, ( errorFound => 1);
    }

    return \@params;
}

# to eliminate html output while running cgi:
sub _print
{}


1;
