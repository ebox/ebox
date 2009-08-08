## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox/CGI/Firewall

nobase_perl_DATA = Object.pm ObjectPolicy.pm ObjectRule.pm ObjectService.pm \
	Deny.pm Redirection.pm Redirects.pm Filter.pm FwdRule.pm FwdRules.pm \
	FwdRuleEdit.pm

SOURCES = $(nobase_perl_DATA)

MAINTAINERCLEANFILES = Makefile.in

EXTRA_DIST = $(nobase_perl_DATA)
