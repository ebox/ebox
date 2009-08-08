package EBox::Sudo;

use strict;
use warnings;

use EBox::Config;
use EBox::Exceptions::Internal;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS  = (all => [qw{ root } ],
			);
	@EXPORT_OK = qw();
	Exporter::export_ok_tags('all');
	$VERSION = EBox::Config::version;
}

sub root($) {
	my $cmd = shift;
	unless (system("/usr/bin/sudo " . $cmd) == 0) {
		throw EBox::Exceptions::Internal("Root command $cmd failed.");
	}
}

sub sudo($$) {
	my ($cmd, $user) = @_;
	unless (system("/usr/bin/sudo -u " . $user . " " . $cmd) == 0) {
		throw EBox::Exceptions::Internal("Running command $cmd as $user failed.");
	}
}

1;
