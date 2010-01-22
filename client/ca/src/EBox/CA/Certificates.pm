# Copyright (C) 2009 eBox Technologies S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Class: EBox::CA::Certificates
#
#

package EBox::CA::Certificates;

use base qw(EBox::CA::Observer);

use strict;
use warnings;

use EBox::Gettext;
use EBox::Global;
use EBox::CA;

use File::Temp qw(tempfile);

# Group: Public methods

# Constructor: new
#
#      Create the new CA Certificates model
#
# Returns:
#
#      <EBox::CA::Certificates> - the recently created model
#
sub new
{
    my $class = shift;

    my $self = {};

    bless($self, $class);

    return $self;
}

# Method: genCerts
#
#      Generates all the certificates requested by all the services
#
sub genCerts
{
    my ($self) = @_;

    my @srvscerts = @{$self->srvsCerts()};
    foreach my $srvcert (@srvscerts) {
        $self->_genCert($srvcert);
    }
}

# Method: certificateRevoked
#
# Overrides:
#
#      <EBox::CA::Observer::certificateRevoked>
#
sub certificateRevoked
{
    my ($self, $commonName, $isCACert) = @_;

    my $ca = EBox::Global->modInstance('ca');
    my $model = $ca->model('Certificates');

    return $model->certUsedByService($commonName);
}

# Method: certificateRenewed
#
# Overrides:
#
#      <EBox::CA::Observer::certificateRenewed>
#
sub certificateRenewed
{
    my ($self) = @_;

    $self->genCerts(); #FIXME only regen renewed certs
}

# Method: certificateExpired
#
# Overrides:
#
#      <EBox::CA::Observer::certificateExpired>
#
sub certificateExpired
{
    my ($self, $commonName, $isCACert) = @_;

    my $ca = EBox::Global->modInstance('ca');
    my $model = $ca->model('Certificates');

    my @srvscerts = @{$self->srvsCerts()};
    foreach my $srvcert (@srvscerts) {
        my $service = $srvcert->{'service'};
        my $cn = $model->cnByService($service);
        if ($cn eq $commonName) {
            $model->disableService($service);
        }
    }
}

# Method: freeCertificate
#
# Overrides:
#
#      <EBox::CA::Observer::freeCertificate>
#
sub freeCertificate
{
    my ($self, $commonName) = @_;

    my $ca = EBox::Global->modInstance('ca');
    my $model = $ca->model('Certificates');

    my @srvscerts = @{$self->srvsCerts()};
    foreach my $srvcert (@srvscerts) {
        my $service = $srvcert->{'service'};
        my $cn = $model->cnByService($service);
        if ($cn eq $commonName) {
            $model->disableService($service);
        }
    }
}

# Method: srvsCerts
#
#      All services which request a certificate as provided
#      by EBox::Module::Service::certificates() plus the
#      module they are from.
#
# Returns:
#
#       A ref to array with all the services information
#
sub srvsCerts
{
    my ($self) = @_;

    my @srvscerts;
    my @mods = @{$self->_modsService()};
    for my $mod (@mods) {
        my @modsrvs = @{EBox::Global->modInstance($mod)->certificates()};
        next unless @modsrvs;
        for my $srv (@modsrvs) {
            $srv->{'module'} = $mod;
            push(@srvscerts, $srv);
        }
    }
    return \@srvscerts;
}


# Group: Public methods

# Method: _genCert
#
#      Generates the certificate for a service
#
sub _genCert
{
    my ($self, $srvcert) = @_;

    my $ca = EBox::Global->modInstance('ca');

    my $model = $ca->model('Certificates');

    my $service = $srvcert->{'service'};
    return undef unless ($model->isEnabledService($service));

    my $cn = $model->cnByService($service);
    return undef unless (defined($cn));

    my $certMD = $ca->getCertificateMetadata(cn => $cn);
    if ((not defined($certMD)) or ($certMD->{state} ne 'V')) {
        # Check the expiration date
        my $caMD = $ca->getCACertificateMetadata();
        $ca->issueCertificate(
            commonName => $cn,
            endDate => $caMD->{expiryDate},
        );
    }

    my $cert = $ca->getCertificateMetadata(cn => $cn)->{'path'};
    my $privkey = $ca->getKeys($cn)->{'privateKey'};

    my ($tempfile_fh, $tempfile) = tempfile(EBox::Config::tmp . "/ca_certificates_XXXXXX") or
        throw EBox::Exceptions::Internal("Could not create temporal file.");

    open(CERT, $cert) or throw EBox::Exceptions::Internal('Could not open certificate file.');
    my @certdata = <CERT>;
    close(CERT);
    open(KEY, $privkey) or throw EBox::Exceptions::Internal('Could not open certificate file.');
    my @privkeydata = <KEY>;
    close(KEY);

    print $tempfile_fh @certdata;
    print $tempfile_fh @privkeydata;
    close($tempfile_fh);

    my $user = $srvcert->{'user'};
    my $group = $srvcert->{'group'};
    EBox::Sudo::root("/bin/chown $user:$group $tempfile");

    my $mode = $srvcert->{'mode'};
    EBox::Sudo::root("/bin/chmod $mode $tempfile");

    my $path = $srvcert->{'path'};
    EBox::Sudo::root("mv -f $tempfile $path");
}

# Method: _modsService
#
#      All configured service modules (EBox::Module::Service)
#      which could be implmenting the certificates method.
#
# Returns:
#
#       A ref to array with all the Module::Service names
#
sub _modsService
{
    my ($self) = @_;

    my @names = @{EBox::Global->modInstancesOfType('EBox::Module::Service')};

    my @mods;
    foreach my $name (@names) {
       $name->configured() or next;
       push (@mods, $name->name());
    }
    return \@mods;
}

1;
