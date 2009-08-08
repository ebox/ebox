package EBox::ProgressIndicator;
#
use strict;
use warnings;

use base 'EBox::GConfModule::StatePartition';

use EBox::Config;
use EBox::Gettext;
use EBox::Global;

use POSIX;

use constant HOST_MODULE => 'apache';

sub create 
{
  my ($class, %params) = @_;
  # check parameter correctness..
  exists $params{totalTicks} or
    throw EBox::Exceptions::MissingArgument('totalTicks named parameter not found');
  ($params{totalTicks} > 0) or
    throw EBox::Exceptions::InvalidData(
				    data  => __('Total ticks'),
				    value => $params{totalTicks},
				    advice => __('It must be a non-zero positive number'),
				   );
  exists $params{executable} or
    throw EBox::Exceptions::MissingArgument('executable named parameter not found');

  my ($executableWoArguments) = split '\s', $params{executable};
  (-x $executableWoArguments) or
    throw EBox::Exceptions::External(
				     __x('Cannot execute  {exe}',
                                           exe => $params{executable}
                                          )
				    );

  # get unique id
  my $hostMod = EBox::Global->modInstance(HOST_MODULE);
  my $id     = $hostMod->st_get_unique_id('', $class->_baseDir);

  # create instance
  my $idKey = $class->_baseDir($id) . '/id';
  $hostMod->st_set_string($idKey, $id);

  my $self = $class->retrieve($id);
  
  # store data
  $self->setConfString('executable', $params{executable});
  $self->setConfInt('totalTicks',    $params{totalTicks});

  $self->setConfInt('ticks', 0);
  $self->setConfString('message', '');
  $self->setConfBool('started', 0);
  $self->setConfBool('finished', 0);

  return $self;
}


sub retrieve
{
  my ($class, $id) = @_;
  defined $id or
    throw EBox::Exceptions::MissingArgument('id');

#  EBox::debug("retieving progress indicator wit hid $id");

  my $baseDir  =  $class->_baseDir($id);
  my $hostMod = EBox::Global->modInstance(HOST_MODULE);
  defined $hostMod or
    throw EBox::Exceptions::Internal('apache module cannot be instantiated');


  $hostMod->st_dir_exists($baseDir) or
    throw EBox::Exceptions::External(
        __x('Progress indicator with id {id} not found', id => $id,  ) 
				    );


  my $self   = $class->SUPER::new($baseDir, $hostMod);
  bless $self, $class;


  return $self;
}


sub new
{
  throw EBox::Exceptions::Internal('Incorrect method: use create or retrieve');
}


sub _baseDir
{
  my ($class, $id) = @_;
  my $dir =  "progress_indicator";
  if ($id) {
    $dir .= "/$id";
  }
  return $dir;
}



sub notifyTick
{
  my ($self, $nTicks) = @_;
  defined $nTicks or
    $nTicks = 1;

  if ($nTicks <= 0) {
    throw EBox::Exceptions::InvalidData(
				    data => __('Number of ticks to notify'),
				    value => $nTicks,
				    advice => __('must be greater than zero'),
				   );
  }

 if (not $self->started) {
    throw EBox::Exceptions::External(
				     __('Executable has not been run')
				    );
  }

  my $newValue = $self->ticks() + $nTicks;
  $self->setConfInt('ticks', $newValue);
}


sub ticks
{
  my ($self) = @_;
  return $self->getConfInt('ticks');
}

sub totalTicks
{
  my ($self) = @_;
  return $self->getConfInt('totalTicks');
}

sub percentage
{
  my ($self) = @_;
  my $per = $self->ticks / $self->totalTicks;
  $per = sprintf("%.2f", $per); # round to two decimals

  return $per;
}

sub setMessage
{
  my ($self, $message) = @_;
  $self->setConfString('message', $message);
}

sub message
{
  my ($self) = @_;
  return $self->getConfString('message');
}


sub id
{
  my ($self) = @_;
  return $self->getConfString('id');
}

sub started
{
  my ($self) = @_;
  return $self->getConfBool('started');
}

sub _setAsStarted
{
  my ($self) = @_;
  return $self->setConfBool('started', 1);
}


sub finished
{
  my ($self) = @_;
  return $self->getConfBool('finished');
}


sub setAsFinished
{
  my ($self) = @_;

  if (not $self->started) {
    throw EBox::Exceptions::External(
	__('The executable has not run')			     
				    );
  }

  $self->setConfBool('finished', 1);
}


sub stateAsString
{
  my ($self) = @_;

  my $totalTicks = $self->totalTicks;
  my $ticks      = $self->ticks;
  my $message     = $self->message;

  my $state;
  if (not $self->started()) {
    $state = 'not running';
  }
  elsif ($self->finished()) {
    if ($ticks < $totalTicks) {
      $state = 'error';
    }
    else {
      $state ='done';
    }
  }
  else {
    $state = 'running';
  }

  my $stString= "state:$state,message:$message,";
  $stString .=  "ticks:$ticks,totalTicks:$totalTicks,";

  return $stString;
}

sub destroy
{
  my ($self) = @_;
  my $piDir = $self->confKeysBase;

  $self->fullModule->st_delete_dir($piDir);
  $_[0] = undef; # to cancel the self value
}


sub _executable
{
  my ($self) = @_;
  return $self->getConfString('executable');
}


sub runExecutable
{
  my ($self) = @_;
  if ($self->started) {
    throw EBox::Exceptions::External(
	__('The executable has already been started')			     
				    );
  }
  elsif ($self->finished) {
    __('The executable has already finished');
  }

  $self->_setAsStarted;

  $self->_fork();
}


sub _fork
{
  my ($self) = @_;

  my $pid = fork();

  unless (defined $pid) {
    throw EBox::Exceptions::Internal("Cannot fork().");
  }

  if ($pid) {
    EBox::debug("parent $$");
    return; # parent returns immediately
  }
  else {
    EBox::debug("child $$");
    $self->_childExec();
  }
}


sub _childExec
{
  my ($self) = @_;

  POSIX::setsid();
#   close(STDOUT);
#   close(STDERR);
#   open(STDOUT, "> /dev/null");
#   open(STDERR, "> /dev/null");

  my $cmd = $self->_executable() .
                  ' ' .
                  $self->execProgressIdParamName() .
                  ' ' . 
		 $self->id();

  EBox::debug("about to execute $cmd");
  exec($cmd);
}


sub execProgressIdParamName
{
  my ($self) = @_;
  return 'progress-id';
}


1;
