package EBox::Test;

use Test::Unit::Procedural;

my @modules = ("EBox::Test::Firewall");

sub testModule($) {
	my $mod = shift;
	create_suite();
	create_suite($mod);
	add_suite($mod);
	run_suite();
}

sub testAllModules {
	create_suite();
	foreach (@modules) {
		create_suite($_);
		add_suite($_);
	}

	run_suite();
}
