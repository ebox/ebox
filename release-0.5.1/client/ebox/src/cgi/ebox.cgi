#!/usr/bin/perl

use strict;
use warnings;

use EBox::Gettext;
use Error qw(:try);
use Data::Dumper;



try {
	use EBox::CGI::Run;
	use EBox::Global;

	EBox::Global::init();
	EBox::CGI::Run->run($ENV{'script'});
}

otherwise  {
	 my $ex = shift;
         use Devel::StackTrace;
	 use CGI qw/:standard/;
	
	 my $trace = Devel::StackTrace->new;
	 print STDERR $trace->as_string;
	 print STDERR Dumper($ex);
	 #TODO Show Jorge make a nice template please
	 print header;
	 print start_html(-title=>'EBox',
	 		  -style=>{'src'=>'/data/css/public.css'});
	 print h1(__('A really nasty bug has occurred'));
	 print end_html;
	 
};
