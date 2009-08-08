package EBox::CGI::Firewall::Object;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Firewall;
use EBox::Objects;
use Net::IPv4Addr qw( :all );

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('template' => '/firewall/object.tmpl',
				      @_);
	bless($self, $class);
	$self->{errorchain} = "Firewall/Index";
	return $self;
}

sub _process($) {
	my $self = shift;
	my $firewall = EBox::Global->modInstance('firewall');
	my $objects = EBox::Global->modInstance('objects');

	$self->_requireParam('object', __('Object'));

	my $objectname = $self->param("object");

	unless ($objects->objectExists($objectname) || $objectname eq "_global") {
		$self->{error} = "Object $objectname does not exist";
		return;
	}

	my $description;

	if ($objectname ne '_global') {
		$description = $objects->getObjectDescription($objectname);
	}

	if ($objectname eq "_global") {
		$self->{title} = "Global Firewall configuration";
	} else {
		$self->{title} = "Firewall configuration: $description";
	}

	my $object = $firewall->Object($objectname);
	my $servs = $firewall->services();
	my $rules = $firewall->ObjectRules($objectname);
	my $objectservs = $firewall->ObjectServices($objectname);
	my $policy = $firewall->ObjectPolicy($objectname);


	foreach (@{$servs}) {
		delete($_->{protocol});
		delete($_->{port});
		if (defined($_->{dnatport})) {
			delete($_->{dnatport});
		}
	}

	my @array = ();

	defined($rules) and push(@array, {'rules' => $rules});
	defined($objectservs) and push(@array, {'servicepol' => $objectservs});

	push(@array, {'object' => $objectname});
	push(@array, {'services' => $servs});
	push(@array, {'policy' => $policy});

	$self->{params} = \@array;
}

1;







