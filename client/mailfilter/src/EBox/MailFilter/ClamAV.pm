package EBox::MailFilter::ClamAV;
# package:
use strict;
use warnings;

use Perl6::Junction qw(any all);
use File::Slurp qw(read_file write_file);
use EBox::Config;
use EBox::Service;
use EBox::Gettext;

use EBox::MailFilter::VDomainsLdap;

use constant {
  CLAMAVPIDFILE                 => '/var/run/clamav/clamd.pid',
  CLAMD_INIT                    => '/etc/init.d/clamav-daemon',
  CLAMD_SERVICE                  => 'ebox.clamd',
  CLAMD_CONF_FILE               => '/etc/clamav/ebox.clamd.conf',

  CLAMD_SOCKET                  => '/var/run/clamav/clamd.ctl',

  FRESHCLAM_CONF_FILE           => '/etc/clamav/freshclam.conf',
  FRESHCLAM_OBSERVER_SCRIPT     => 'freshclam-observer',  
  FRESHCLAM_CRON_SCRIPT         => '/etc/cron.hourly/freshclam',
};




sub new 
{
  my $class = shift @_;

  my $self = {};
  bless $self, $class;

  return $self;
}

sub _mailfilterModule
{
  return EBox::GconfModule::Partition::fullModule(@_);
}

sub usedFiles
{
  return (
#         {
#          file => CLAMD_CONF_FILE,
#          reason => __(' To configure clamd daemon'),
#          module => 'mailfilter',
#         },
          {
           file => FRESHCLAM_CONF_FILE,
           reason => __('To configure freshclam updater daemon'),
           module => 'mailfilter',
          },
         );
}


sub doDaemon
  {
    my ($self, $mailfilterService) = @_;

    if ($mailfilterService and $self->service() and $self->isRunning()) {
      $self->_daemon('restart');
    } 
    elsif ($mailfilterService and $self->service()) {
      $self->_daemon('start');
    } 
    elsif ($self->isRunning()) {
      $self->_daemon('stop');
    }
  }





sub _daemon
{
  my ($self, $action) = @_;

  if ($action ne all('start', 'stop', 'restart')) {
    throw EBox::Exceptions::Internal("Bad argument: $action");
  }

  EBox::Service::manage(CLAMD_SERVICE, $action);
}






sub service
{
  my ($self) = @_;

  my $mailfilter = EBox::Global->modInstance('mailfilter');
  my $avConf     = $mailfilter->model('AntivirusConfiguration');
  return $avConf->enabled();
}


sub setVDomainService
{
  my ($self, $vdomain, $service) = @_;

  my $vdomainsLdap = EBox::MailFilter::VDomainsLdap->new();
  $vdomainsLdap->checkVDomainExists($vdomain);
  $vdomainsLdap->setAntivirus($vdomain, $service);
}


sub vdomainService
{
  my ($self, $vdomain) = @_;

  my $vdomainsLdap = EBox::MailFilter::VDomainsLdap->new();
  $vdomainsLdap->checkVDomainExists($vdomain);
  $vdomainsLdap->antivirus($vdomain);
}


# we ignore freshclam running state
sub isRunning
{
  my ($self) = @_;

  return 1 if $self->_clamdRunning();

  return 0;
}


sub stopService
{
  my ($self) = @_;

  if ($self->isRunning()) {
    $self->_daemon('stop');
  }
}




sub _clamdRunning
{
  my ($self) = @_;

  return EBox::Service::running(CLAMD_SERVICE);
}



sub localSocket
{
  return CLAMD_SOCKET;
}



sub writeConf
{
  my ($self, $globalService) = @_;

  my $localSocket = $self->localSocket();

  my @clamdParams = (
                localSocket => $localSocket,
               );

  EBox::Module->writeConfFile(CLAMD_CONF_FILE, "mailfilter/clamd.conf.mas", \@clamdParams);



  my $observerScript = EBox::Config::share() . '/ebox-mailfilter/' .  FRESHCLAM_OBSERVER_SCRIPT;

  my @freshclamParams = (
                         clamdConfFile   => CLAMD_CONF_FILE,
                         observerScript  => $observerScript,
                        );


  EBox::Module->writeConfFile(FRESHCLAM_CONF_FILE, "mailfilter/freshclam.conf.mas", \@freshclamParams);

  my $antivirusService = $self->service;
  if ($antivirusService and $globalService) {
    # regenerate freshclam cron hourly script
    EBox::Module->writeConfFile(FRESHCLAM_CRON_SCRIPT, "mailfilter/freshclam-cron.mas", []);
    EBox::Sudo::root('chmod a+x ' . FRESHCLAM_CRON_SCRIPT);
  }
  else {
    # remove freshclam cron hourly entry
    my $rmCmd = 'rm -f ' . FRESHCLAM_CRON_SCRIPT;
    EBox::Sudo::root($rmCmd);
  }
}



#   
#
#
sub freshclamState
{
  my ($self) = @_;
  my @stateAttrs = qw(update error outdated date);

  my $freshclamStateFile = $self->freshclamStateFile();
  if (not -e $freshclamStateFile) {
    return { map {  ( $_ => undef )  } @stateAttrs  }; # freshclam has never updated before
  }


  my $fileContents  =  read_file($freshclamStateFile);
  my %state =  split ',', $fileContents, (@stateAttrs * 2);

  # checking state file coherence
  foreach my $attr (@stateAttrs) {
    exists $state{$attr} or throw EBox::Exceptions::Internal("Invalid freshclam state file. Missing attribute: $attr");
  }
  if ( scalar @stateAttrs !=  scalar keys %state) {
    throw EBox::Exceptions::Internal("Invalid fresclam state file: invalid attributes found. (valid attributes are @stateAttrs)");
  }


  return \%state;
}


#XXX fix
sub freshclamStateFile
{
  '/var/run/clamav/freshclam.state';
}

sub notifyFreshclamEvent
{
  my ($class, $event, $extraParam) = @_;

  my @validEvents = qw(update error outdated);
  if (not ($event eq any( @validEvents))) {
    $extraParam = defined $extraParam ? "with parameter $extraParam" : "";
    die ("Invalid freshclam event: $event $extraParam");
  }


  my $date = time();
  my $update   = 0;
  my $outdated = 0;
  my $error    = 0;


  if ($event eq 'update') {
    $update = 1;
  }
  elsif ($event eq  'error') {
    $error = 1;
  }
  elsif ($event eq 'outdated') {
    $outdated = $extraParam; # $extraPAram = last version

  }


  my $statePairs = "date,$date,update,$update,error,$error,outdated,$outdated";
  write_file($class->freshclamStateFile(), $statePairs);
}


1;
