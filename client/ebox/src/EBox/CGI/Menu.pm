# Copyright (C) 2008 eBox Technologies S.L.
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

package EBox::CGI::Menu;

use strict;
use warnings;

use base 'EBox::CGI::ClientRawBase';

use EBox::Config;
use EBox::Menu;

use Error qw(:try);
use JSON;
use Storable qw(retrieve);

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	return $self;
}

# Method: requiredParameters
#
# Overrides:
#
#   <EBox::CGI::Base::requiredParameters>
#
sub requiredParameters
{
    return ['search'];
}

# Method: actuate
#
# Overrides:
#
#   <EBox::CGI::Base::actuate>
#
sub actuate
{
    my ($self) = @_;
    my $search = $self->param('search');
    my $menuclass = $self->{namespace} . '::Menu';

    eval "use $menuclass";
    my $file = $menuclass->cacheFile();
    unless (-f $file) {
        $menuclass->regenCache();
    }
    my $keywords = retrieve($file);
    my @search_items = split(/\W+/, $search);

    my $sections = {};
    my @words = keys(%{$keywords});
    for my $it (@search_items) {
        my @fullwords = grep(/^$it/,@words);
        my $cur = {};
        for my $word (@fullwords) {
            my $sects = $keywords->{$word};
            for my $sect (@{$sects}) {
                if(not defined($cur->{$sect})) {
                    $cur->{$sect} = 1;
                }
            }
        }
        for my $sect (keys %{$cur}) {
            if(not defined($sections->{$sect})) {
                $sections->{$sect} = 0;
            }
            $sections->{$sect}++;
        }
    }
    $self->{sections} = [];
    for my $sect (keys %{$sections}) {
        if($sections->{$sect} == @search_items) {
            push(@{$self->{sections}}, $sect);
        }
    }
}

sub _print
{
	my ($self) = @_;
    print($self->cgi()->header(-charset=>'utf-8',-type=>'application/json'));

    my $js = objToJson($self->{sections});
    print $js;
}

1;
