## Process this file with automake to produce Makefile.in
SUBDIRS=Report

perldir = @PERLPATH@/EBox/Firewall/Model

nobase_perl_DATA = InternalToEBoxRuleTable.pm ToInternetRuleTable.pm \
		ExternalToEBoxRuleTable.pm EBoxOutputRuleTable.pm RedirectsTable.pm \
		ExternalToInternalRuleTable.pm BaseRuleTable.pm EBoxServicesRuleTable.pm

DISTCLEANFILES =

EXTRA_DIST = $(nobase_perl_DATA)

MAINTAINERCLEANFILES = Makefile.in
