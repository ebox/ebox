## Process this file with automake to produce Makefile.in
SUBDIRS = Server Client  LogHelper t Model Types

perldir = @PERLPATH@/EBox/OpenVPN

nobase_perl_DATA = Server.pm FirewallHelper.pm  Daemon.pm Client.pm LogHelper.pm

test_classes = Test.pm

DISTCLEANFILES =

EXTRA_DIST = $(nobase_perl_DATA) $(test_classes)

MAINTAINERCLEANFILES = Makefile.in
