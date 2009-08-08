## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox/CGI

nobase_perl_DATA = Base.pm Finish.pm Run.pm General.pm Password.pm Lang.pm \
	Port.pm

SUBDIRS = Objects Firewall Login Logout Network Summary

SOURCES = $(nobase_perl_DATA)

MAINTAINERCLEANFILES = Makefile.in

EXTRA_DIST = $(nobase_perl_DATA)
