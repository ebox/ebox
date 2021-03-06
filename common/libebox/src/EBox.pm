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

package EBox;

use strict;
use warnings;

use EBox::Config;
use EBox::Exceptions::DeprecatedMethod;
use POSIX qw(setuid setgid setlocale LC_ALL LC_NUMERIC);
use English;

use constant CHECK_DBUS_CMD =>'ebox-dbus-check';
use constant LOGGER_CAT => 'EBox';

my $loginit = 0;

sub deprecated
{
	my $debug = EBox::Config::configkey('debug');
	if ($debug eq 'yes') {
		throw EBox::Exceptions::DeprecatedMethod();
	}
}

sub info # (msg)
{
	my ($msg) = @_;
	my $logger = EBox::logger(LOGGER_CAT);
	$Log::Log4perl::caller_depth +=1;
	$logger->info($msg);
	$Log::Log4perl::caller_depth -=1;
}

sub error # (msg)
{
	my ($msg) = @_;
	my $logger = EBox::logger(LOGGER_CAT);
	$Log::Log4perl::caller_depth +=1;
	$logger->error($msg);
	$Log::Log4perl::caller_depth -=1;
}

sub debug # (msg)
{
	my ($msg) = @_;
	my $logger = EBox::logger(LOGGER_CAT);
	$Log::Log4perl::caller_depth +=1;
	$logger->debug($msg);
	$Log::Log4perl::caller_depth -=1;
}

sub warn # (msg)
{
	my ($msg) = @_;
	my $logger = EBox::logger(LOGGER_CAT);
	$Log::Log4perl::caller_depth +=1;
	$logger->warn($msg);
	$Log::Log4perl::caller_depth -=1;
}

sub initLogger
{
    my ($conffile) = @_;
    my $umask = umask(022);
    unless ($loginit) {
        Log::Log4perl->init(EBox::Config::conf() . '/' . $conffile);
        $loginit = 1;
    }
    umask($umask);
}

# returns the logger for the caller package, initLogger must be called before
sub logger # (caller?)
{
	my ($cat) = @_;
	defined($cat) or $cat = LOGGER_CAT;
	if(not $loginit) {
            use Devel::StackTrace;

            my $trace = Devel::StackTrace->new();
            print STDERR $trace->as_string();
        }
	return Log::Log4perl->get_logger($cat);
}

# arguments
# 	- locale: the locale the interface should use
sub setLocale # (locale)
{
	my ($locale) = @_;
	open(LOCALE, ">" . EBox::Config::conf() . "/locale");
	print LOCALE $locale;
	close(LOCALE);
}

# returns:
# 	- the locale
sub locale
{
	my $locale="C";
	if (-f (EBox::Config::conf() . "locale")) {
		open(LOCALE, EBox::Config::conf() . "locale");
		$locale = <LOCALE>;
		close(LOCALE);
	}
	return $locale;
}

sub init
{
	POSIX::setlocale(LC_ALL, EBox::locale());
	POSIX::setlocale(LC_NUMERIC, 'C');

	my @groups = @{EBox::Config::groups()};
	my $gids = '';
	for my $group (@groups) {
		$gids .= getgrnam($group) . ' ';
	}
	$GID = $EGID = getgrnam(EBox::Config::group()) . " $gids";

	my $user = EBox::Config::user();
	my $uid = getpwnam($user);
	setuid($uid) or die "Cannot change user to $user. Are you root?";

        EBox::initLogger('eboxlog.conf');
        dbusInit();

        # Set HOME environment variable to avoid some issues calling
        # external programs
        $ENV{HOME} = EBox::Config::home();
}

# Method: dbusInit
#
#      Initialise a dbus daemon, if it's not already done. We store
#      one for root and one for eBox user.
#
#
sub dbusInit
{
	my $gconfversion = `gconftool-2 -v`;
	$gconfversion =~ m/^(\d+)\.(\d+)\./;
	my $minor = $2;
	if ($minor <= 22) {
		return;
	}

	my $confFile;
	if ( POSIX::getuid() == 0) {
		$confFile = EBox::Config::conf() . 'dbus-root-session.conf';
	} else {
		$confFile = EBox::Config::conf() . 'dbus-ebox-session.conf';
	}

	for my $i (1..30) {
		# Check we actually can connect to dbus
        system( EBox::Config::pkgdata() .  CHECK_DBUS_CMD);
		last if ( $? == 0 );
		sleep(1);
	}
	my $dbusAddress = EBox::Config::configkeyFromFile('DBUS_SESSION_BUS_ADDRESS', $confFile);
	$ENV{DBUS_SESSION_BUS_ADDRESS} = $dbusAddress;
}

1;
