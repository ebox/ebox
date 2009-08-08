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

use EBox::Global;
use EBox::Config;
use EBox::Gettext;

sub header # (title) 
{
	$title = shift;

	return qq%
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
		      "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Ebox - $title</title>
<link href="/data/css/public.css" rel="stylesheet" type="text/css" />
<script type="text/javascript" src="/data/js/common.js">//</script>
</head>
<body>%
}

sub title
{
	return '<div id="header">' . "" . "</div>";
}

#Order a menu by attribute order
#Order can be: [first['+'dig]|last['-'dig]|any]
#If order is undef it assumes 'any'. If user makes
#an error such as using same position for two elements, the second one is
#changed to any.
#returns
#	- an ordered menu array
sub _orderMenu
{
	my $global = EBox::Global->getInstance();
	my @menu = @{$global->menuEntries};
	my @order;
	foreach (@menu){
		if ($_->{'order'}) {
			my $index;
			my ($pos, $op, $offset ) = $_->{'order'}
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
				$_->{'order'} = 'any';
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

sub menu
{
	my $menu = "<div id='menu'>\n<ul class='menu'>\n";
	my $entries = _orderMenu();

	foreach (@{$entries}) {
		my $text = $_->{'text'};
		my $url = $_->{'location'};
	
		#Check if there is a style defined for this entry
		if ( defined $_->{'style'} ){
			$menu .= "<li class='" . $_->{'style'} . "'>\n";
		}else{
			$menu .= "<li>\n";
		}
		if( defined($url) ) {
			$menu .= "<a title='" . $text . "' ";
			$menu .= "href='/ebox/" . $url . "' ";
			$menu .= "target='_parent'>";
			$menu .= $text;
			$menu .= "</a>\n";
		}else{
			$menu .= $text;
		}
		if( defined($_->{'sub'})){
			my $sub = $_->{'sub'};
			$menu .= "<ul class='submenu'>\n";
			foreach(@{$sub}){
				$menu .= "<li>\n";
				$menu .= "<a title='" . $_->{'text'} . "' ";
				$menu .= "href='/ebox/" . $_->{'location'} . "' ";
				$menu .= "target='_parent'>";
				$menu .= $_->{'text'};
				$menu .= "</a>";
				$menu .= "</li>\n";
			}
			$menu .= "</ul>\n";
		}
		$menu .= "</li>\n";
	}
	$menu .= '</ul></div></div><div id="content">';

	return $menu;
}

sub footer
{
	return qq%</div>
		  <div id="footer">
	Copyright &copy; 2004, <a href='http://www.warp.es'>Warp Networks S.L.</a>
		  </div>
	<script type="text/javascript" src="/data/js/help.js">//</script>
	</body>
	</html>
%;
}

1;
