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

package EBox::Html;

my $localedir = EBox::Config::share . "/locale";
eval "use Locale::TextDomain ('ebox', \"$localedir\");";

use EBox::Global;
use EBox::Config;

sub header($) {
	$title = shift;

	return qq%
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
		      "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Ebox - $title</title>
<link href="/data/css/public.css" rel="stylesheet" type="text/css" />
</head>

<body>%
}

sub title() {
	return '<div id="header">' . "" . "</div>";
}

#Order a menu by attribute order
#Order can be: [first['+'dig]|last['-'dig]|any]
#If order is undef it assumes 'any'. If user makes
#an error such as using same position for two elements, the second one is
#changed to any.
#returns
#	- an ordered menu array
sub _orderMenu() {
	my $global = EBox::Global->modInstance('global');
	my @menu = @{$global->menuEntries};
	my @order;
	foreach (@menu){
		if ($_->[2]) {
			my $index;
			my ($pos, $op, $offset ) = $_->[2] 
				=~ /(first|last|any)\s*(\+|\-)?\s*(\d+)?/i;
			if ( $pos =~ /first/i ){
				$index = $offset ? $offset : 0;
			}elsif ( $pos =~ /last/i and not $offset ){
				$index = $#menu;
			}elsif ( $pos =~ /last/i ){
				$index = $#menu - $offset;
			}
			if ( not defined $order[$index]){
				$order[$index] = $_;
				undef $_;
			}else{
				$_->[2] = 'any';
			}
		}
	}
	@menu = grep defined, @menu;
	foreach (@order){
		$_ = pop @menu if ( not $_ ); 
	}
	@order = grep defined, @order;
	return \@order;
}

sub menu() {
	my $menu = '<div id="menu"><ul>';
	my $entries = _orderMenu();

	foreach (@{$entries}) {
		my $text = @{$_}[0];
		my $url = @{$_}[1];
	
		if ( $text =~ m{^__(.*)$} ) {
			$text = eval($text);
		}
		#Check if there is a style defined for this entry
		if ( defined @{$_}[3] ){
			$menu .= '<div id="'. @{$_}[3] . '">';
		}else{
			$menu .= '<li>';
		}
		$menu .= '<a title="' . $text . '" ';
		$menu .= 'href="/ebox/' . $url . '" ';
		$menu .= 'target="_parent">';
		$menu .= $text;
		$menu .= '</a>';
		if ( defined @{$_}[3] ){
			$menu .= '</div>';
		}else{
			$menu .= '</li>';
		}
	}

	$menu .= '</ul></div><div id="content">';

	return $menu;
}

sub footer() {
	return qq%</div>
		  <div id="footer">
	Copyright &copy; 2004, <a href='http://www.warp.es'>Warp Networks S.L.</a>
		  </div>
	</body>
	</html>
%;
}

1;
