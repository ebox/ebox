package EBox::CGI::Run;

use strict;
use warnings;

use EBox::CGI::Base;
use EBox::Global;
use CGI;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub run($$){
	shift;
	my $script = shift;	
	my $classname = "EBox::CGI::";

	defined($script) or exit;

	$script =~ s/\?.*//g;
	$script =~ s/[\\"']//g;
	$script =~ s/\//::/g;
	$script =~ s/^:://;

	$classname .= $script;

	$classname =~ s/::::/::/g;
	$classname =~ s/::$//;

	if ($classname eq 'EBox::CGI') {
		$classname .= '::Summary::Index';
	}

	my $log = EBox::Global->logger;
	$log->info("Creating cgi: $classname");

	my $cgi;
	eval "use $classname"; 
	if ($@) {
		$log->error("Unable to import cgi: $classname");
		$cgi = new EBox::CGI::Base(
			error => __("The page could not be found"));
	} else {
		$cgi = new $classname;
	}
	$cgi->run;
}

1;
