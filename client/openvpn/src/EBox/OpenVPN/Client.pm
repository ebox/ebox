package EBox::OpenVPN::Client;
# Description: Class for modelling each of the OpenVPN servers
use strict;
use warnings;

use base qw(EBox::OpenVPN::Daemon);

use EBox::Validate qw(checkPort checkAbsoluteFilePath checkIP checkDomainName);
use EBox::NetWrappers;
use EBox::CA;
use Perl6::Junction qw(all);
use List::Util qw(first);
use EBox::Gettext;
use Params::Validate qw(validate_pos SCALAR);


sub new
{
    my ($class, $name, $openvpnModule) = @_;
   
    my $prefix= 'client';

    my $self = $class->SUPER::new($name, $prefix, $openvpnModule);
      bless $self, $class;

    return $self;
}



sub _setConfPath
{
  my ($self, $key, $path, $prettyName) = @_;

  checkAbsoluteFilePath($path, __($prettyName));
  $self->setConfString($key, $path);
}


sub setProto
{
    my ($self, $proto) = @_;

    if ($proto ne 'tcp'  and ($proto ne 'udp') ) {
	throw EBox::Exceptions::InvalidData(data => "client's protocol", value => $proto, advice => __("The protocol only may be tcp or udp.")  );
    }

    $self->setConfString('proto', $proto);
}

sub proto
{
    my ($self) = @_;
    return $self->getConfString('proto');
}


sub caCertificatePath
{
  my ($self) = @_;
  return $self->getConfString('caCertificatePath');
}

sub setCaCertificatePath
{
  my ($self, $path) = @_;
  my $prettyName = q{Certification Authority's certificate};
  $self->_setConfPath('caCertificatePath', $path, $prettyName);
}


sub certificatePath
{
  my ($self) = @_;
  return $self->getConfString('certificatePath');
}

sub setCertificatePath
{
  my ($self, $path) = @_;
  my $prettyName = q{client's certificate};
  $self->_setConfPath('certificatePath', $path, $prettyName);
}


sub certificateKey
{
  my ($self) = @_;
  return $self->getConfString('certificateKey');
}

sub setCertificateKey
{
  my ($self, $path) = @_;
  my $prettyName = q{certificate's key};
  $self->_setConfPath('certificateKey', $path, $prettyName);
}




sub setService # (active)
{
  my ($self, $active) = @_;
  ($active and $self->service)   and return;
  (!$active and !$self->service) and return;

  $self->setConfBool('active', $active);
}


sub service
{
   my ($self) = @_;
   return $self->getConfBool('active');
}


sub confFileTemplate
{
  my ($self) = @_;
  return "openvpn/openvpn-client.conf.mas";
}

sub confFileParams
{
  my ($self) = @_;
  my @templateParams;

  my @paramsNeeded = qw(caCertificatePath certificatePath certificateKey  user group proto );
  foreach my $param (@paramsNeeded) {
    my $accessor_r = $self->can($param);
    defined $accessor_r or die "Can not found accesoor for param $param";
    my $value = $accessor_r->($self);
    defined $value or next;
    push @templateParams, ($param => $value);
  }

  push @templateParams, (servers =>  $self->servers() );


  return \@templateParams;
}

sub servers
{
  my ($self) = @_;

  my @serverAddrs = @{ $self->allConfEntriesBase('servers') };
  my @servers = map {
    my $port = $self->getConfInt("servers/$_");
    [ $_ => $port ]
  } @serverAddrs;

  
  return \@servers;
}


sub setServers
{
  my ($self, $servers_r) = @_;
  my @servers = @{ $servers_r };
  (@servers > 0) or throw EBox::Exceptions::External(__('You must supply at least one server for the client'));

  $self->deleteConfDir('servers');

  foreach my $serverParams_r (@servers) {
    $self->addServer(@{  $serverParams_r  });
  }
}


sub addServer
{
  my ($self, $addr, $port) = @_;

  if (!checkDomainName($addr) && !checkIP($addr)) {
    throw EBox::Exceptions::InvalidData(
					data => __('Server address'), 
					value => $addr,
				       );
  }

  checkPort($port, __(q{Server's port}));

  $self->setConfInt("servers/$addr", $port);
}

sub removeServer
{
  my ($self, $addr) = @_;

  my $serverKey = "servers/$addr";

  if (!$self->confDirExists($serverKey)) {
    throw EBox::Exceptions::External("Requested server does not exist");
  }


  $self->unsetConf($serverKey);
}

sub init
{
    my ($self, %params) = @_;

    (exists $params{proto}) or throw EBox::Exceptions::External __("A IP protocol must be specified for the server");
    (exists $params{caCertificatePath}) or throw EBox::Exceptions::External __("A path to the CA certificate must be specified");
    (exists $params{certificatePath}) or throw EBox::Exceptions::External __("A path to the client certificate must be specified");
    (exists $params{certificateKey}) or throw EBox::Exceptions::External __("A path to the client certificate key must be specified");
    (exists $params{servers}) or throw EBox::Exceptions::External __("Servers msut be supplied yo yhe client");
    exists $params{service} or $params{service} = 0;


    my @attrs = qw(proto caCertificatePath certificatePath certificateKey servers service);
    foreach my $attr (@attrs)  {
	if (exists $params{$attr} ) {
	    my $mutator_r = $self->can("set\u$attr");
	    defined $mutator_r or die "Not mutator found for attribute $attr";
	    $mutator_r->($self, $params{$attr});
	}
    }
}



1;
