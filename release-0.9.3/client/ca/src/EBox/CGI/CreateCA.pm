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

package EBox::CGI::CA::CreateCA;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;
use EBox;

# Method: new
#
#       Constructor for CreateCA CGI
#
# Returns:
#
#       CreateCA - The object recently created

sub new
  {

    my $class = shift;

    my $self = $class->SUPER::new('title' => __('Certification Authority Management'),
				  @_);

    $self->{domain} = "ebox-ca";
    $self->{redirect} = "CA/Index";
    bless($self, $class);

    return $self;

  }

# Process the HTTP query

sub _process
  {

    my $self = shift;

    my $ca = EBox::Global->modInstance('ca');

    $self->_requireParam('orgName', __('Organization Name') );
    $self->_requireParam('expiryDays', __('Days to expire') );

    my $orgName = $self->param('orgName');
    my $days = $self->param('expiryDays');

    if ( $days <= 0 ) {
      throw EBox::Exceptions::External(__('Days to expire MUST be a natural number'));
    }

    my $retVal = $ca->createCA( orgName       => $orgName,
				days          => $days);

    if (not defined($retVal) ) {
      throw EBox::Exceptions::External(__('Problems creating Certification Authority has happened'));
    }

  }

1;
