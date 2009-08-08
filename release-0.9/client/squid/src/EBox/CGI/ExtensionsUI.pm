# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
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

package EBox::CGI::Squid::ExtensionsUI;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Gettext;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title'    => __('HTTP Proxy'),
				      'template' => 'squid/filterTable.mas',
				      @_);
	$self->{domain} = 'ebox-squid';
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	$self->{title} = __('HTTP Proxy');

	my $squid = EBox::Global->modInstance('squid');
	my @array;
	# Elements to filter
	push (@array, 'elements'       => $squid->hashedExtensions());
	# The title for the list
	push (@array, 'title'          => __("Configure allowed extensions"));
	# CGI to call to change filters
	push (@array, 'name'           => "extension");
	# Name of attribute to filter (Internationalized)
	push (@array, 'printableName'  => __("Extension"));
	# Help message
	push (@array, 'helpMessage'    => __('Add a new file extension without dot. Like "pdf"'));
	$self->{params} = \@array;
}

1;
