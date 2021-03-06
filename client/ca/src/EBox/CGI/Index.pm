# Copyright (C) 2006-2007 Warp Networks S.L.
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

package EBox::CGI::CA::Index;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;

# Method: new
#
#       Constructor for Index CGI
#
# Returns:
#
#       Index - The object recently created

sub new
  {

    my $class = shift;

    my $self = $class->SUPER::new('title'  => __('Certification Authority'),
				  @_);

    $self->{domain} = 'ebox-ca';
    bless($self, $class);

    return $self;

  }

# Method: masonParameters
#
# Overrides:
#
#     <EBox::CGI::Base::masonParameters>
#
sub masonParameters
  {

    my $self = shift;

    my $ca = EBox::Global->modInstance('ca');

    # Check if the CA infrastructure has been created
    my @array = ();

    if ( $ca->isCreated() ) {
      $self->{'template'} = "ca/index.mas";
      # Update CA DB prior to displaying certificates
      $ca->updateDB();
      push( @array, 'certs' => $ca->listCertificates() );

      # Check if a new CA certificate is needed (because of revokation from RevokeCertificate)
      my $currentState = $ca->currentCACertificateState();
      if ( $currentState =~ m/[RE]/) {
	push( @array, 'caNeeded' => 1);
      } else {
        push( @array, 'passRequired' => $ca->passwordRequired() );
      }
    } else {
      $self->{'template'} = "ca/createCA.mas";
    }

    return \@array;
  }


1;
