#!/usr/bin/perl

use strict;
use warnings;

use EBox::CGI::Run;
use EBox::Global;
use POSIX qw(setlocale LC_ALL);

my $global = EBox::Global->modInstance('global');
POSIX::setlocale(LC_ALL,$global->locale());

EBox::CGI::Run->run($ENV{'script'});
