## Process this file with automake to produce Makefile.in
perldir = @PERLPATH@/EBox/Mail

SUBDIRS = Model Composite Types

regular_packages = FilterProvider.pm Greylist.pm FetchmailLdap.pm

test_packages = Test.pm

nobase_perl_DATA=  $(regular_packages)

DISTCLEANFILES =

EXTRA_DIST = $(regular_packages) $(test_packages)

MAINTAINERCLEANFILES = Makefile.in
