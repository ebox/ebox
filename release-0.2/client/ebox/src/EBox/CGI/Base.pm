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

package HTML::Template::Expr;
my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

package EBox::CGI::Base;
use strict;
use warnings;

use HTML::Template;
use HTML::Template::Expr;
use CGI;
use EBox::Global;
use EBox::Html;
use EBox::Exceptions::Base;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;
use EBox::Exceptions::DataMissing;
use POSIX qw(setlocale LC_ALL);
use Error qw(:try);

## arguments
##		title [optional]
##		error [optional]
##		cgi   [optional]
##		template [optional]
sub new {
	my $class = shift;
	my %opts = @_;
	my $self = {};
	my $global = EBox::Global->modInstance('global');
	POSIX::setlocale(LC_ALL,$global->locale());
	$self->{title} = delete $opts{title}; $self->{error} = delete $opts{error}; $self->{msg} = delete $opts{msg}; $self->{cgi} = delete $opts{cgi};
	$self->{template} = delete $opts{template};
	unless (defined($self->{cgi})) {
		$self->{cgi} = new CGI;
	}
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
	my $filename = EBox::Config::templates . '/title.tmpl';
	my $template = HTML::Template::Expr->new(filename => $filename);
	$template->param('title' => $self->{title});
	print($template->output);
}

sub _error($) {
	my $self = shift;
	defined($self->{error}) or return;
	my $filename = EBox::Config::templates . '/error.tmpl';
	my $template = HTML::Template::Expr->new(filename => $filename);
	$template->param('error' => $self->{error});
	print($template->output);
}

sub _msg($) {
	my $self = shift;
	defined($self->{msg}) or return;
	my $filename = EBox::Config::templates . '/msg.tmpl';
	my $template = HTML::Template::Expr->new(filename => $filename);
	$template->param('msg' => $self->{msg});
	print($template->output);
}

sub _body($) {
	my $self = shift;
	defined($self->{template}) or return;

	my $filename = EBox::Config::templates . $self->{template};
	my $template = HTML::Template::Expr->new(filename => $filename);

	$template->register_function( __ => \&Locale::TextDomain::__  );

	if (defined($self->{params})) {
		foreach (@{$self->{params}}) {
			$template->param($_);
		}
	}

	print($template->output());
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
	use locale;
	my $global = EBox::Global->modInstance('global');
	POSIX::setlocale(LC_ALL,$global->locale());
	foreach (@names) {
		my $val = $cgi->param($_);
		defined($val) or next;
		unless ( $val =~ m{^[\w /.?:-]*$} ) {
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

sub run($) {
	my $self = shift;

	if (not $self->_loggedIn) {
		$self->{redirect} = "/ebox/Login/Index";
	} elsif ($self->_sanitize) { 
		try {
			$self->_process;
		} catch EBox::Exceptions::External with {
			my $ex = shift;
			$self->{error} = $ex->text;
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
		} catch EBox::Exceptions::Internal with {
			$self->{error} = "An internal error has ocurred. " . 
				"This is most probably a bug, relevant ". 
				"information can be found in the logs.";
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
		} catch EBox::Exceptions::Base with {
			$self->{error} = "An unknown internal error has ".
				"ocurred. This is a bug, relevant ". 
				"information can be found in the logs.";
			if (defined($self->{redirect})) {
				$self->{chain} = $self->{redirect};
			}
		};
	}
	
	if (defined($self->{error}) && defined($self->{errorchain})) {
		if ($self->{errorchain} ne "") {
			$self->{chain} = $self->{errorchain};
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
	defined($value) or return undef;
	$value =~ s/^ +//;
	$value =~ s/ +$//;
	return $value;
}

sub params($) {
	my $self = shift;
	my $cgi = $self->cgi;
	my @names = $cgi->param;
	return \@names;
}
	
sub cgi($) {
	my $self = shift;
	return $self->{cgi};
}


1;
