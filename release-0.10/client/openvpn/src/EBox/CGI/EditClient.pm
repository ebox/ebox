package EBox::CGI::OpenVPN::EditClient;
# Description:
use strict;
use warnings;
use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;
use EBox::Config;
use EBox::OpenVPN;
use Perl6::Junction qw(any);
use File::Basename;
use File::Slurp qw(read_file write_file);

my @clientPropierties = qw(proto caCertificatePath certificatePath certificateKey  service);
my @serverPropierties  = qw(serverAddr serverPort); # this special treatment is due because the module is ready to use more than one server but no the CGIs.

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('OpenVPN'),
				      'template' => '/openvpn/editClient.mas',
				      @_);
	$self->{domain} = 'ebox-openvpn';
	bless($self, $class);
	return $self;
}


sub requiredParameters
{
    my ($self) = @_;
    if ($self->param('edit')) {
	return ['name', 'edit'];
    }
    else {
	return ['name'];
    }
}


sub optionalParameters
{
    my ($self) = @_;
 
    my @optional;

    # we add the parameters from the scripts which redirect here
    @optional = qw(name network netmask submit);

    if ($self->param('edit')) {
	push @optional, (@clientPropierties, @serverPropierties);
    }

    return \@optional;
}


sub masonParameters
{
    my ($self) = @_;

    my $name = $self->param('name');
    $name or throw EBox::Exceptions::External('No client name provided');

    my $openVPN = EBox::Global->modInstance('openvpn');
    my $client = $openVPN->client($name);

    my %clientAttributes;
    foreach my $attr (@clientPropierties) {
	my $accessor_r = $client->can($attr);
	defined $accessor_r or throw EBox::Exceptions::Internal "Can not locate accessor for $attr in client class";
	my $value = $accessor_r->($client);
	$clientAttributes{$attr} = $value;
    }


    my ($serverAddr, $serverPort) = $self->_getServerPropierties($client);
    $clientAttributes{serverAddr} = $serverAddr;
    $clientAttributes{serverPort} = $serverPort;


    return [
	    name => $name, 
	    clientAttrs => \%clientAttributes,  
	   ];
}





sub actuate
{
  my ($self) = @_;

  my $name = $self->param('name');
  my $openVPN = EBox::Global->modInstance('openvpn');
  my $client = $openVPN->client($name);

  if ($client->internal) {
    $self->setErrorchain('OpenVPN/Index');
    throw EBox::Exceptions::Internal("The client $name doesn't allow UI modification");
  }


  if ($self->param('edit')) {
    $self->_doEdit($name, $client);
  }

}




sub _doEdit
{
  my ($self, $name, $client) = @_;

  my $changed = 0;

  my $anyPropiertyParam = any @clientPropierties;

  my @mutatorsParams = grep { $_ eq $anyPropiertyParam } @{ $self->params() };
  my $anyParamWithUpload = any(qw(caCertificatePath certificatePath certificateKey));  

  foreach my $attr (@mutatorsParams) {
    my $value =  $self->param($attr);
    next if $value eq '';

    if ($attr eq $anyParamWithUpload) {
      $value = $self->upload($attr); # value must be the file path, not the
                                     # parameter value 
    }
    else {
	  $value = $self->param($attr);
	}


    if ($client->$attr() ne $attr) {
      my $mutatorName = "set\u$attr";
      my $mutator_r   = $client->can($mutatorName);
      defined $mutator_r or throw EBox::Exceptions::Internal "$mutatorName not found in client object";

      $mutator_r->($client, $value);
      $changed = 1;
    }
  }

  if ($self->param('serverAddr') ||  $self->param('serverPort')) {
    my ($newServerAddr, $newServerPort) = ($self->param('serverAddr'), $self->param('serverPort'));
    my ($oldServerAddr, $oldServerPort) = $self->_getServerPropierties($client);

      my $serverAddr  = defined $newServerAddr ? $newServerAddr : $oldServerAddr;
      my $serverPort  = defined $newServerPort ? $newServerPort : $oldServerPort;

      my @newServers = ([$serverAddr, $serverPort],);
      $client->setServers(\@newServers);
  }

    
  if ($changed) {
    $self->setMsg(__x("Client {name} configuration updated", name => $name) );
    $self->{chain} = 'OpenVPN/Index';
  } 
  else {
    $self->setMsg( __('There are no changes to be saved'));
  }
}


# XXX we assume we have only one server!
sub _getServerPropierties
{
  my ($self, $client) = @_;
  my @servers = @{ $client->servers()  };

  return (undef, undef) if (@servers == 0);

  my ($serverAddr, $serverPort) = @{ $servers[0] };
  return ($serverAddr, $serverPort);
}





1;

