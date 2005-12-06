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

package EBox::CGI::Mail::QueueManager;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::Gettext;
use EBox::Mail;
use EBox::MailQueue qw( :all );
use POSIX qw(ceil);

use constant PAGESIZE => 15;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new('title'    => __('Queue Management'),
				      'template' => 'mail/qmanager.mas',
				      @_);
	$self->{domain} = 'ebox-mail';
	bless($self, $class);
	return $self;
}

sub _process($) {
	my $self = shift;
	$self->{title} = __('Queue Management');
	my $mail = EBox::Global->modInstance('mail');
	use Data::Dumper;

	my @array = ();

	my @mqlist = @{mailQueueList()};

	my $page = 1;
#	if(defined($self->params('page'))) {
#		$page = $self->params('page');
#	}

	my $info = $self->param('getinfo');
	unless ($self->param('getinfo')) {
		$info = 'none';
	}
	my @data = ('');
	if ($info ne 'none') {
		@data = @{infoMail($info)};
	}
	
	my $aux = ($page - 1) * PAGESIZE;
	my @showlist;
	if (($aux + PAGESIZE - 1) >= (scalar(@mqlist) - 1)) {
		print STDERR "First: $aux, Last: ".(scalar(@mqlist) - 1) ."\n";
		@showlist = @mqlist[$aux..(scalar(@mqlist) - 1)];
	} else {
		@showlist = @mqlist[$aux..($aux + PAGESIZE - 1)];
	}
	
	my $tpages = ceil(scalar(@mqlist) / PAGESIZE);
	
	push(@array, 'mqlist'		=> \@showlist);
	push(@array, 'page'	=> $page);
	push(@array, 'tpages'	=> $tpages);
	push(@array, 'getinfo'	=> $info);
	push(@array, 'data'	=> \@data);

	$self->{params} = \@array;
}
1;
