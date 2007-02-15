use strict;
use warnings;
use Cwd;

use lib '../..';
use EBox::Test::Mason;
use File::Basename;

use Test::More tests => 7;

my $printOutput = 0;
my $outputFile  = '/tmp/select.html';
system "rm -rf $outputFile";

my $compRoot =   dirname dirname getcwd();
my $template =   (dirname getcwd()) . '/select.mas';


my @options = (
	       { value => 'baboon' },
	       { value => 'mandrill', printableValue => 'mandrill printable value'},
	       { value => 'gibon', printableValue => 'gibon printable value'},
	      );


my @nameAndValue = (name => 'monkeys', value => 'mandrill');


my @cases = (
	     [ name => 'monos' ],  # minimal case
	     [@nameAndValue],
	     [@nameAndValue, options => \@options],
	     [@nameAndValue, extraParams => [options => \@options] ],
	     [@nameAndValue, options => \@options, extraParams => [ options => [ value => 'Bad option' ] ]  ], 
	     [@nameAndValue, options => \@options, extraParams => [ disabled => 'disabled'] ],
	     [@nameAndValue, options => \@options, extraParams => [ multiple => 'multiple'] ],
	    );


foreach my $params (@cases) {
  EBox::Test::Mason::checkTemplateExecution(template => $template, templateParams => $params, compRoot => [$compRoot], printOutput => $printOutput, outputFile => $outputFile);
}

1;
