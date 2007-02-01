package EBox::CGI::OpenVPN::CreateClient;
# Description:
use strict;
use warnings;
use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;
use EBox::OpenVPN;
use Perl6::Junction qw(any);
use File::Slurp;
use File::Basename;

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('OpenVPN'),
				      'template' => '/openvpn/createClient.mas',
				      @_);

	$self->{domain} = 'ebox-openvpn';
	bless($self, $class);
	return $self;
}


sub requiredParameters
{
    my ($self) = @_;
    if ($self->param('create')) {
	[qw(create name proto caCertificatePath certificatePath certificateKey serverAddr serverPort service)];
    }
    else {
	return [];
    }

}


sub optionalParameters
{
    my ($self) = @_;
    if ($self->param('create')) {
	[qw( service )];
    }
    else {
	return [qw(submit)];
    }
}




sub actuate
{
    my ($self) = @_;
 
    if ($self->param('create')) {
	my $openVPN = EBox::Global->modInstance('openvpn');

	my $anyParamWithUpload = any(qw(caCertificatePath certificatePath certificateKey));

	my $name;
	my %params;

	foreach my $param (@{ $self->params() }) {
	  EBox::debug("param $param");
	  if ($param eq 'name') {
	    $name = $self->param('name');
	    next;
	  }

	  my $paramValue;
	  if ($param eq $anyParamWithUpload) {
	    $paramValue = $self->_upload($param);
	  }
	  else {
	    $paramValue = $self->param($param);
	  }

	  $params{$param} = $paramValue;
	} 


	# for now we only suport one server
	my $serverAddr = delete $params{serverAddr};
	my $serverPort = delete $params{serverPort};
	my @servers = (
		       [$serverAddr => $serverPort],
		      );

	# remove blank parameters
	while (my ($key, $value) = each %params) {
	    next if $value ne '';
	    delete $params{$key};
	}

	$openVPN->newClient($name, servers => \@servers, %params);

    
	$self->setMsg(__x("New client {name} created", name => $name) );
	$self->{chain} = 'OpenVPN/Index';
    }
}


sub _upload
{
  my ($self, $param) = @_;

  my $path = $self->cgi->param($param);
  $path or return;

  my $newFile = '/tmp/' . basename $path;


  # get upload contents
  my $UPLOAD_FH = $self->cgi->upload($param);
  if (not $UPLOAD_FH) {
    throw EBox::Exceptions::External( __('Invalid file.'));
  }

  my $fileContent = read_file($UPLOAD_FH, scalar_ref => 1);
  close $UPLOAD_FH;

  # write to destination file
  EBox::Sudo::command(" touch $newFile");
  EBox::Sudo::command("chmod 0600 $newFile");
  write_file ($newFile, $fileContent);
  
  return $newFile;
}


1;

