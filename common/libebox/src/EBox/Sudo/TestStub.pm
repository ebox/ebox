package EBox::Sudo::TestStub;
# Description:
# 
use strict;
use warnings;

#use Test::MockModule;
use EBox::Sudo;

# XXX There are problems with symbol imporation and Test::MockModule
# until we found a solution we will use a brute redefiniton
# XXX Currently i see not way for mocking EBox::Sudo::sudo
# XXX there are unclaer situation with comamnds containig ';' but this is also de case of EBox::Sudo

#my $mockedSudoModule = undef;

my $oldRootSub = undef;

sub fake
{
    $oldRootSub = \&EBox::Sudo::root if !defined $oldRootSub;

    no warnings 'redefine';
    my $redefinition = '
    sub EBox::Sudo::root
    {
	return EBox::Sudo::TestStub::_fakedRoot(@_);
    }';

    eval $redefinition;
   if ($@) {
    throw EBox::Exceptions::Internal ("Error while redifinition of root for test purposes: $@");
  }

}


# XXX fix:  restores behaviour but no implementation 
sub unfake
{
    defined $oldRootSub or die "Module was not mocked";


    no warnings 'redefine';
    my $redefinition = ' sub EBox::Sudo::root
     {
 	return $oldRootSub->(@_);
     }';

    eval $redefinition;
    if ($@) {
	throw EBox::Exceptions::Internal ("Error while redifinition of root for test purposes: $@");
    }

}


sub _fakedRoot
{
    my ($cmd) = @_;

    my @output = `$cmd`;
    unless($? == 0) {
	_rootCommandException($cmd, $!);
    }
    return \@output;
}



sub _rootCommandException
{
    my ($cmd, $error) = @_;
    throw EBox::Exceptions::Internal("(Mocked EBox::Sudo) Root command $cmd failed. $error");
}



1;
