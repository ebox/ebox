# Copyright (C) 2006 Warp Networks S.L.
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

package EBox::CGI::CA::IssueCertificate;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;

# Method: new
#
#       Constructor for IssueCertificate CGI
#
# Returns:
#
#       IssueCertificate - The object recently created

sub new
  {

    my $class = shift;

    my $self = $class->SUPER::new('title' => __('Certification Authority Management'),
				  @_);

    $self->{domain} = "ebox-ca";
    $self->{chain} = "CA/Index";
    bless($self, $class);

    return $self;

  }

# Process the HTTP query

sub _process
  {

    my $self = shift;

    my $ca = EBox::Global->modInstance('ca');

    my $issueCA = $self->param('caNeeded');
    $issueCA = 0 unless defined($issueCA);

    if ($issueCA) {
      $self->_requireParam('name', __('Organization Name') );
    } else {
      $self->_requireParam('name', __('Common Name') );
    }
    # Common parameters
    $self->_requireParam('expiryDays', __('Days to expire') );

    my $name = $self->param('name');
    my $days = $self->param('expiryDays');

    if ( $days <= 0 ) {
      throw EBox::Exceptions::External(__('Days to expire MUST be a natural number'));
    }

    # Only valid chars minus '/' --> security risk
    unless ( index ( $name, '/' ) == -1 ) {
      throw EBox::Exceptions::External(__('The input contains invalid ' .
					  'characters. All alphanumeric characters, ' .
					  'plus these non alphanumeric chars: .?&+:\@ ' .
					  'and spaces are allowed.'));
    }

    my $retValue;
    if ($issueCA) {
      $retValue = $ca->issueCACertificate( orgName       => $name,
					   days          => $days,
					   genPair       => 1);
    } else {
      $retValue = $ca->issueCertificate( commonName    => $name,
					 days          => $days);
    }

    my $msg = __("The certificate has been issued");
    $msg = __("The new CA certificate has been issued") if ($issueCA);
    $self->setMsg($msg);

  }

1;
