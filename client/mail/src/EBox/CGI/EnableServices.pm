# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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

package EBox::CGI::Mail::EnableServices;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Gettext;

## arguments:
## 	title [required]
sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title' => 'Mail', @_);
	$self->{redirect} = "Mail/Index";	
	$self->{domain} = "ebox-mail";	
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	my $mail = EBox::Global->modInstance('mail');

	my $pop = $self->param('pop');
	my $imap = $self->param('imap');
	my $filter = $self->param('filter');
	my $popssl = $self->param('popssl');
	my $imapssl = $self->param('imapssl');

	$mail->setService(defined($pop), 'pop');
	$mail->setService(defined($imap), 'imap');
	$mail->setService(defined($filter), 'filter');

	if (defined($popssl)) {
		$mail->setSslPop($popssl);
	}
	if (defined($imapssl)) {
		$mail->setSslImap($imapssl);
	}
}

1;
