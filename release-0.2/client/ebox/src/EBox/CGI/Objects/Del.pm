# Copyright (C) 2004  Warp Netwoks S.L.
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

package EBox::CGI::Objects::Del;

use strict;
use warnings;

use base 'EBox::CGI::Base';

use EBox::Global;
use EBox::Exceptions::DataInUse;
use Error qw(:try);

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	$self->{redirect} = "/Objects/Index";
	return $self;
}

sub _process($) {
	my $self = shift;
	my $objects = EBox::Global->modInstance('objects');
	$self->_requireParam('objectname', __('Object name'));

	if (defined($self->param("deleteforce"))) {
		$objects->delObjectForce($self->param("objectname"));
		return;
	} elsif (defined($self->param("cancel"))) {
		return;
	}

	try {
		$objects->delObject($self->param("objectname"));
	} catch EBox::Exceptions::DataInUse with {
		$self->{template} = '/objects/delete.tmpl';
		$self->{redirect} = undef;
		my @array = ();
		push(@array, {'object' => $self->param("objectname")});
		push(@array, {'description' =>
			$objects->getObjectDescription($self->param("objectname"))});
		$self->{params} = \@array;
	};
}

1;
