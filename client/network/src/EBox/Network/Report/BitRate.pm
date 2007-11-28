package EBox::Network::Report::BitRate;
#
use strict;
use warnings;

use RRDs;

use EBox::Global;
use EBox::Gettext;
use EBox::Config;
use EBox::Exceptions::Internal;
use EBox::NetWrappers;
use EBox::ColourRange;

use File::Glob qw(:glob);
use File::Basename;

use Params::Validate qw(validate SCALAR);

use constant RRD_TTL => 601; 

use constant SRC_COLOUR      => 'FF0000';
use constant SERVICE_COLOUR =>  '00FF00';
use constant SRC_AND_SERVICE_COLOUR => '0000FF';

use constant SERVICE_KEY => 'usage-monitor-active';


use constant MONITOR_DAEMON => '/usr/lib/ebox/ebox-traffic-monitor';

use constant CONF_FILE => '/etc/jnettop.conf';

# XX DEBUG
    use DB;
our @ISA = qw(DB);

sub service
{
  my ($class) = @_;
  my $network  = EBox::Global->modInstance('network');
  return $network->get_bool(SERVICE_KEY)
}


sub setService
{
  my ($class, $newService) = @_;

  my $network  = EBox::Global->modInstance('network');
  my $oldService = $network->get_bool(SERVICE_KEY);
  if ($newService xor $oldService) {
    $network->set_bool(SERVICE_KEY, $newService);
  }
}



sub running
{
  my ($class) = @_;

  system 'pgrep -f ' . MONITOR_DAEMON;
  return ($? == 0);
}

sub _regenConfig
{
  my ($class) = @_;

  my $service = $class->service;
  my $running = $class->running();

  if ($running) {
    $class->stopService();
  }
  
  if ( $service) {
    $class->_writeConfFile();
    EBox::Sudo::root(MONITOR_DAEMON . ' time 10 ' . ' conffile ' . CONF_FILE);
  }

}


sub stopService
{
  my ($class) = @_;
  EBox::Sudo::root('pkill -f ' . MONITOR_DAEMON);
}


sub _writeConfFile
{
  my ($class) = @_;

  my $network = EBox::Global->modInstance('network');
  my @internalIfaces = @{ $network->InternalIfaces()  };

  my @localNets = map {
    my $net = $network->ifaceNetwork($_);
    my ($addr, $mask) = EBox::NetWrappers::to_network_without_mask($net);
    [$addr, $mask]
  } @internalIfaces;

  EBox::Module->writeConfFile(
			      CONF_FILE,
			      'network/jnettop.conf.mas',
			      [ localNetworks => \@localNets,  ]

			     );
}

my %srcBps;
my %serviceBps;
my %srcAndServiceBps;

sub addBps
{
  my %params = @_;

  validate (@_, {
		 proto => { TYPE => SCALAR },
		 src => { TYPE => SCALAR },
		 sport => { TYPE => SCALAR },
		 dst => { TYPE => SCALAR },
		 dport => { TYPE => SCALAR },
		 bps => { TYPE => SCALAR },
		});


  EBox::debug("addBps @_");

  my $src = $params{src};


  my $proto = $params{proto};
  my $sport = $params{sport};
  my $dst = $params{dst};
  my $dport = $params{dport};
  my $bps  = $params{bps};


  my $service = _service($proto, $dport, $sport);

  print "addBps: src $src service $service\n";

  # store the values waitng for flush..
  $srcBps{$src}         += $bps;
  $serviceBps{$service} += $bps;

  my $srcAndServiceId = "$src|$service";
  $srcAndServiceBps{$srcAndServiceId} += $bps;
}


sub flushBps
{
  while (my ($src, $bps) = each %srcBps) {
    addBpsToSrcRRD($src, $bps);
  }

  while (my ($service, $bps) = each %serviceBps) {
    addBpsToServiceRRD($service, $bps);
  }
  
  while (my ($id, $bps) = each %srcAndServiceBps) {
    my ($src, $service) = split '\|', $id, 2;
    addBpsToSrcAndServiceRRD($src, $service, $bps);
  }
  
  %srcBps     = ();
  %serviceBps = ();
  %srcAndServiceBps = ();
}


sub  _service
{
  my ($proto, $dport, $sport) = @_;
  my $service;

  if ($proto eq 'arp') {
    return 'arp';
  }

  $service = getservbyport($dport, $proto);

  if (not $service and ($sport ne 'AGGR.')) {
    $service = getservbyport($sport, $proto);
  }

  if (not $service) {
    $service = $proto . $dport;
  }

  return $service;
}



sub _addBpsToRRD
{
  my ($rrd, $bps) = @_;

  _createRRDIfNotExists($rrd);

  RRDs::update($rrd, "N:$bps");
  my $err = RRDs::error;
  if ( $err) {

    my $stack = __PACKAGE__->backtrace;

   throw EBox::Exceptions::Internal " error updating $rrd: $err\nstack: $stack";
  }
}


sub _rrdDir
{
  return EBox::Config::tmp() . 'rrd/';
}


sub srcRRD
{
  my ($src) = @_;
  

  my $rrd =  _rrdDir() . 'src-' . $src . '.rrd';

  print "SRC: $src RRD: $rrd\n";
  return $rrd;
}

sub serviceRRD
{
  my ($service) = @_;
  my $rrd =  _rrdDir() . 'service-'. $service . '.rrd';
  return $rrd;
}


sub srcAndServiceRRD
{
  my ($src, $service) = @_;
  my $rrd =  _rrdDir() . "src-$src-service-$service.rrd";
  return $rrd;
}

sub _createRRDIfNotExists
{
  my ($rrd) = @_;
  if ( -f $rrd) {
    return;
  }

  RRDs::create(
	       $rrd,
	       '-s 1',
	       'DS:bps:GAUGE:60:0:U',
	       'RRA:AVERAGE:0.99:2:600', # store 10 minutes of data
	      );


  my $err = RRDs::error;
  if ( $err) {
    die $err;
  }
}


sub addBpsToSrcRRD
{
  my ($src, $bps) = @_;
  my $rrd = srcRRD($src);

  _addBpsToRRD($rrd, $bps);
}

sub addBpsToServiceRRD
{
  my ($service, $bps) = @_;

  my $rrd = serviceRRD($service);

  _addBpsToRRD($rrd, $bps);
}

sub addBpsToSrcAndServiceRRD
{
  my ($src, $service, $bps) = @_;

  my $rrd = srcAndServiceRRD($src, $service);

  _addBpsToRRD($rrd, $bps);
}



sub _activeRRDs
{
  my ($rrds_r) = @_;

  my $now = time();
  my $threshold = $now -  RRD_TTL;

  my @active;
  foreach my $rrd (@{ $rrds_r }) {
    my $lastUpdate = RRDs::last($rrd);
    my $err        = RRDs::error;
    if ($err) {
      EBox::error("Error getting last update time of RRD $rrd: $err");
      next;
    }

    if ($lastUpdate < $threshold ) {
      _removeRRD($rrd);
      next;
    }

    push @active, $rrd;
  }

  return \@active;
}



sub _removeRRD
{
  my ($rrd) = @_;

  unlink $rrd;

  # remove related RRDs
  my $dir  = _rrdDir();
  my $relatedGlob = basename $rrd;
  $relatedGlob =~ s{\.rrd$}{};
  $relatedGlob = "$dir/*" . $relatedGlob . '*.rrd';
  
  my @relatedFiles = bsd_glob($relatedGlob);
  foreach (@relatedFiles) {
    unlink $_;
  }
}

sub activeServiceRRDs
{
  my $dir = _rrdDir();
  my @rrds = bsd_glob("$dir/service-*.rrd");
  @rrds = @{ _activeRRDs(\@rrds) };

  return \@rrds;
}


sub activeSrcRRDs
{
  my $dir = _rrdDir();
  my @rrds = bsd_glob("$dir/src-*.rrd");
  @rrds = grep {
    not ($_ =~ m/-service-/)  # discard rrds of src + service aggregation
  } @rrds;

  @rrds = @{ _activeRRDs(\@rrds) };

  return \@rrds;
}


# XXX add params validation
sub graph
{
  my %params = @_;

  my @dataset   = @{ $params{dataset} };
  my $startTime = $params{startTime};
  my $title     = $params{title};

  my $file      = $params{file};

  my $verticalLabel = __('bytes/second');

  my $step = 1; # time step one second

  my @defs;
  my @lines;
  my $i = 0;
  foreach my $ds (@dataset) {
    my $rrd    = $ds->{rrd};
    my $colour = $ds->{colour};
    my $legend = $ds->{legend};

    my $vname = "v$i";

    push @defs, "DEF:$vname=$rrd:bps:AVERAGE";
    push @lines, "LINE2:$vname#$colour:$legend";

    $i++;
  }



  RRDs::graph(
	      $file,  
	      "-s $startTime",
	      "-S $step",
	      "-t $title",
	      "-v $verticalLabel",
	      @defs,
	      @lines,
	     );

  my $error = RRDs::error;
  if ($error) {
    throw EBox::Exceptions::Internal("rrdgraph error: $error");
  }
}



sub srcGraph
{
  my (%params) = @_;

  my $src = delete $params{src};
  my $rrd = srcRRD($src);
  if (not -f $rrd) {
    throw EBox::Exceptions::External( 
				     __x(
					 'Traffic data not found for source {src}',
					 src => $src,
					)
				    );
  }

  my $dataset = [
		 _srcDatasetElement($src, $rrd),
		];


  my $title =__x('Network traffic from {src}', src => $src);

  graph(
	dataset => $dataset,
	title   => $title,
	%params,
       );
}

sub serviceGraph
{
  my (%params) = @_;

  my $service = delete $params{service};
  my $rrd = serviceRRD($service);
  if (not -f $rrd) {
    throw EBox::Exceptions::External( 
				     __x(
				     'Traffic data not found for service {service}',
				     service => $service,
					 )
				    );
  }

  my $dataset = [
		 _serviceDatasetElement($service, $rrd),
		];


  my $title =__x('Network traffic for {service}', service => $service);

  graph(
	dataset => $dataset,
	title   => $title,
	%params,
     );
}

sub srcAndServiceGraph
{
  my (%params) = @_;

  my $src     = delete $params{src};
  my $service = delete $params{service};

  my $srcRRD = srcRRD($src);
  if (not -f $srcRRD) {
    throw EBox::Exceptions::External( 
				     __x(
					'Traffic data not found for source {src}',
					src => $src,
				       )
				    );
  }

  my $serviceRRD  = serviceRRD($service);  
  if (not -f $serviceRRD) {
    throw EBox::Exceptions::External(
				     __x(
				     'Traffic data not found for service {service}',
				     service => $service,
					)
				    );
  }

  my $srcAndServiceRRD = srcAndServiceRRD($src, $service);
  if (not -f $srcAndServiceRRD) {
    throw EBox::Exceptions::External( 
				     __x(
				     'Traffic data not found for source {src} and service {service}',
				     src     => $src,
				     service => $service,
				     )
				    );
  }

  my $dataset = [
		 _srcDatasetElement($src, $srcRRD),
		 _serviceDatasetElement($service, $serviceRRD),
		 _srcAndServiceDatasetElement($src, $service, $srcAndServiceRRD),
		];


  my $title =__x('Network traffic from source {src} and for service {service}', 
		 src     => $src,
		 service => $service,
		);

  graph(
	dataset => $dataset,
	title   => $title,
	%params,
     );
}

sub activeServicesGraph
{
  my %params = @_;

  my $title = __('Active services');

  my @services = @{  activeServiceRRDs()  };  
  @services or
    throw EBox::Exceptions::External(
				     __('No services bit rate data found')
				    );

  my @colours = @{ EBox::ColourRange::range(scalar @services) };

  my @dataset;
  foreach my $service (@services) {
    # extract service name
    $service =~ m/service-(.*)\.rrd/;
    my $legend = $1;
    my $ds = {
	      rrd     => $service,
	      legend => $legend,
	      colour => pop @colours,
	     };
    
    push @dataset, $ds;
  }
  
  graph(
	dataset => \@dataset,
	title   => $title,
	%params,
     );
}


sub activeSrcsGraph
{
  my %params = @_;

  my $title = __('Active sources');

  my @srcs = @{  activeSrcRRDs()  };  
  @srcs or
    throw EBox::Exceptions::External(
				     __('No sources bit rate data found')
				    );

  my @colours = @{ EBox::ColourRange::range(scalar @srcs) };

  my @dataset;
  foreach my $src (@srcs) {
    # extract src name
    $src =~ m/src-(.*)\.rrd/;
    my $legend = $1;
    my $ds = {
	      rrd     => $src,
	      legend => $legend,
	      colour => pop @colours,
	     };
    
    push @dataset, $ds;
  }
  
  graph(
	dataset => \@dataset,
	title   => $title,
	%params,
     );
}

sub _srcDatasetElement
{
  my ($src, $rrd) = @_;

  my $legend = __x("Traffic rate from {src}", src => $src);

  my $ds = {
	  rrd => $rrd,
	  legend => $legend,
	  colour => SRC_COLOUR,
	 };

  return $ds;
}

sub _serviceDatasetElement
{
  my ($service, $rrd) = @_;

  my $legend = __x("Traffic rate for {service}", service => $service);

  my $ds = {
	  rrd => $rrd,
	  legend => $legend,
	  colour => SERVICE_COLOUR,
	 };

  return $ds;
}

sub _srcAndServiceDatasetElement
{
  my ($src, $service, $rrd) = @_;

  my $legend = __x("Traffic rate from {src} for {service}", 
		   src     => $src,
		   service => $service,
		  );

  my $ds = {
	  rrd => $rrd,
	  legend => $legend,
	  colour => SRC_AND_SERVICE_COLOUR,
	 };

  return $ds;
}


1;
