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

package EBox::Loggerd;

use EBox;
use EBox::Global;
use EBox::Sudo qw( :all );
use EBox::Gettext;
use EBox::DBEngineFactory;
use EBox::Exceptions::Internal;

use IO::Handle;
use IO::File;
use IO::Select;
use File::Tail;

use POSIX;

use constant BUFFER => 64000;

# Safe signal usage
my ($piperd, $pipewr);

sub int_handler
{
    syswrite $pipewr, 1, 1;
}

sub new
{
    my $class = shift;
    my $self = {};
    my %opts = @_;
    $self->{'filetails'} = [] ;
    bless($self, $class);
    return $self;
}

sub run
{
    my ($self) = @_;

    $self->initDaemon();
    EBox::init();

    my $global = EBox::Global->getInstance();
    my $log = $global->modInstance('logs');
    $self->{'loghelpers'} = $log->allEnabledLogHelpers();
    $self->{'dbengine'} = EBox::DBEngineFactory::DBEngine();
    $self->_prepare();
    $self->_mainloop();
}


sub initDaemon
{
    my ($self) = @_;

    unless (POSIX::setsid) {
        EBox::debug ('Cannot start new session for ', $self->{'name'});
        exit 1;
    }

    foreach my $fd (0 .. 64) { POSIX::close($fd); }

    my $tmp = EBox::Config::tmp();
    open(STDIN,  "+<$tmp/stdin");
    if (EBox::Config::configkey('debug') eq 'yes') {
        open(STDOUT, "+>$tmp/stout");
        open(STDERR, "+>$tmp/stderr");
    }

}




# Method: _prepare
#
#       Init the necessary stuff, such as open fifos, use required classes, etc.
#
sub _prepare # (fifo)
{
    my ($self) = @_;

    pipe $piperd, $pipewr;
    $SIG{"INT"} = \&int_handler;

    my @loghelpers = @{$self->{'loghelpers'}};
    for my $obj (@loghelpers) {
        for my $file (@{$obj->logFiles()}) {
            my $tail;
            eval {
                $tail = File::Tail->new(name => $file,
                                        interval => 1, maxinterval => 1,
                                        ignore_nonexistant => 1)
               };

            if ($@) {
                EBox::warn($@);
                next;
            }
            push @{$self->{'filetails'}}, $tail;
            push @{$self->{'objects'}->{$file}}, $obj;
        }
    }

}

sub _mainloop
{
    my ($self) = @_;
    my $rin;

    my @files = @{$self->{'filetails'}};
    while(@files) {
        vec($rin, fileno($piperd), 1) = 1;
                my ($nfound, $timeleft, @pending)=
                    File::Tail::select($rin, undef, undef, undef , @files);
        if ($nfound > @pending) {
            EBox::info "Exiting Loggerd\n";
            exit 0;
        }
        foreach my $file (@pending) {
            my $path = $file->{'input'};
            my $buffer = $file->read();
            if (defined($buffer) and length ($buffer) > 0) {
                for my $obj (@{$self->{'objects'}->{$path}}) {
                    foreach my $line (split(/\n/, $buffer)) {
                        eval {$obj->processLine($path, $line,
                                                $self->{'dbengine'})};
                                        }
                }
            }
        }

    }

}


1;

