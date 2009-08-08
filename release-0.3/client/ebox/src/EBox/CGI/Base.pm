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

package EBox::CGI::Base;
use strict;
use warnings;

use HTML::Mason;
use CGI;
use EBox::Gettext;
use EBox::Global;
use EBox::Html;
use EBox::Exceptions::Base;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;
use EBox::Exceptions::DataMissing;
use POSIX qw(setlocale LC_ALL);
use Error qw(:try);
use Encode qw(:all);

## arguments
##		title [optional]
##		error [optional]
##		cgi   [optional]
##		template [optional]
sub new {
	my $class = shift;
	my %opts = @_;
	my $self = {};
	#my $global = EBox::Global->getInstance();
	#POSIX::setlocale(LC_ALL,$global->locale());
	$self->{title} = delete $opts{title};
	$self->{error} = delete $opts{error};
	$self->{msg} = delete $opts{msg};
	$self->{cgi} = delete $opts{cgi};
	$self->{template} = delete $opts{template};
	unless (defined($self->{cgi})) {
		$self->{cgi} = new CGI;
	}
	$self->{domain} = 'ebox';
	$self->{paramsKept} = ();
	bless($self, $class);
	return $self;
}

sub _header($) {
	my $self = shift;
	print($self->cgi()->header(-charset=>'utf-8'));
	print(EBox::Html::header($self->{title}));
}

sub _top($) {
	my $self = shift;
	print(EBox::Html::title());
}

sub _menu($)  {
	my $self = shift;
	print(EBox::Html::menu);
}

sub _title($) {
	my $self = shift;
	my $filename = EBox::Config::templates . '/title.mas';
	my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::templates);
	my $comp = $interp->make_component(comp_file => $filename);
	my @params = ();
	push(@params, 'title' => $self->{title});

	settextdomain('ebox');
	$interp->exec($comp, @params);
	settextdomain($self->{domain});
}

sub _error($) {
	my $self = shift;
	defined($self->{error}) or return;
	my $filename = EBox::Config::templates . '/error.mas';
	my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::templates);
	my $comp = $interp->make_component(comp_file => $filename);
	my @params = ();
	push(@params, 'error' => $self->{error});
	$interp->exec($comp, @params);
}

sub _msg($) {
	my $self = shift;
	defined($self->{msg}) or return;
	my $filename = EBox::Config::templates . '/msg.mas';
	my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::templates);
	my $comp = $interp->make_component(comp_file => $filename);
	my @params = ();
	push(@params, 'msg' => $self->{msg});
	$interp->exec($comp, @params);
}

sub _body($) {
	my $self = shift;
	defined($self->{template}) or return;

	my $filename = EBox::Config::templates . $self->{template};
	my $interp = HTML::Mason::Interp->new(comp_root => EBox::Config::templates);
	my $comp = $interp->make_component(comp_file => $filename);
	$interp->exec($comp, @{$self->{params}});
}

sub _footer($) {
	my $self = shift;
	print(EBox::Html::footer);
}

sub _print($) {
	my $self = shift;
	$self->_header;
	$self->_top;
	$self->_menu;
	$self->_title;
	$self->_error;
	$self->_msg;
	$self->_body;
	$self->_footer;
}

sub _process($) {
	my $self = shift;
}

sub _sanitize($) {
	my $self = shift;
	my $cgi = $self->cgi;
	my @names = $cgi->param;
	my $global = EBox::Global->getInstance();
	POSIX::setlocale(LC_ALL,$global->locale());
	use locale;
	foreach (@names) {
		my $val = $cgi->param($_);
		_utf8_on($val);
		my $name = $_;
		defined($val) or next;
		unless ( $val =~ m{^[\w /.?:-]*$} ) {
			my $logger = EBox::Global->logger;
			$logger->info("Invalid characters in param $name, ".
				      "value $val.");
			$self->{error} ='The input contains invalid characters';
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
			return undef;
		}
	}
	no locale;
	return 1;
}

sub _loggedIn($) {
	my $self = shift;
	# TODO
	return 1;
}

sub _urlToChain($) {
	my $str = shift;
	$str =~ s/\?.*//g;
	$str =~ s/\//::/g;
	$str =~ s/::$//g;
	$str =~ s/^:://g;
	return "EBox::CGI::" . $str;
}

# arguments
# 	- name of the required parameter
# 	- display name for the parameter (as seen by the user)
sub _requireParam($$$) {
	my ($self, $param, $display) = @_;

	unless (defined($self->param($param)) && $self->param($param) ne "") {
		throw EBox::Exceptions::DataMissing(data => $display);
	}
}

# arguments
# 	- name of the required parameter
# 	- display name for the parameter (as seen by the user)
sub _requireParamAllowEmpty($$$) {
	my ($self, $param, $display) = @_;

	unless (defined($self->param($param))) {
		throw EBox::Exceptions::DataMissing(data => $display);
	}
}

sub run($) {
	my $self = shift;
	my $error;
	if (not $self->_loggedIn) {
		$self->{redirect} = "/ebox/Login/Index";
	} elsif ($self->_sanitize) { 
		try {
			$self->_process;
		} catch EBox::Exceptions::External with {
			my $ex = shift;
			$error = $ex->text;
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
		} catch EBox::Exceptions::Internal with {
			$error = __("An internal error has ocurred. " . 
				"This is most probably a bug, relevant ". 
				"information can be found in the logs.");
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
		} catch EBox::Exceptions::Base with {
			$error = __("An unknown internal error has ".
				"ocurred. This is a bug, relevant ". 
				"information can be found in the logs.");
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
		} otherwise {
			my $e = shift;
			$error = __("You have just hit a bug in EBox. Please, report it to Warp Networks");
		};
	}
	
	if (defined($error)) {
		$self->{error} = $error;

		#only keep the parameters in paramsKept
		my $params = $self->params;
		foreach my $param (@{$params}) {
			unless (grep /^$param$/, @{$self->{paramsKept}}) {
				$self->{cgi}->delete($param);
			}
		}
		if(defined($self->{errorchain})) {
			if ($self->{errorchain} ne "") {
				$self->{chain} = $self->{errorchain};
			}
		}
	}

	if (defined($self->{chain})) {
		my $classname = _urlToChain($self->{chain});
		eval "use $classname";
		my $chain = $classname->new('error' => $self->{error},
					    'cgi'   => $self->{cgi});
		$chain->run;
		return;
	} elsif ((defined($self->{redirect})) && (!defined($self->{error}))) {
		print($self->cgi()->redirect("/ebox/" . $self->{redirect}));
		return;
	} else {
		$self->_print;
	}
}

sub param($$) {
	my ($self, $param) = @_;
	my $cgi = $self->cgi;
	my $value = $cgi->param($param);
	#check if exists $param.x for input type=image
	unless (defined($value)){
		$value = $cgi->param($param . ".x");
	}
	defined($value) or return undef;
	$value =~ s/^ +//;
	$value =~ s/ +$//;
	_utf8_on($value);
	return $value;
}

sub params($) {
	my $self = shift;
	my $cgi = $self->cgi;
	my @names = $cgi->param;
	return \@names;
}

sub keepParam($$){
	my ($self, $param) = @_;
	push(@{$self->{paramsKept}}, $param);
}

sub cgi($) {
	my $self = shift;
	return $self->{cgi};
}

sub domain(){
	my $self = shift;
	return $self->{domain};
}

1;
