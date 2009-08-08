## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox

nobase_perl_DATA = Module.pm Html.pm Schema.pm Config.pm Validate.pm \
	Network.pm Global.pm Firewall.pm Iptables.pm Objects.pm \
	Test.pm SysInfo.pm XMLModule.pm \
	Test/Firewall.pm Test/Squid.pm Sudo.pm Auth.pm Order.pm

SUBDIRS = CGI Exceptions Summary

DISTCLEANFILES = Config.pm

MAINTAINERCLEANFILES = Makefile.in

EXTRA_DIST = $(nobase_perl_DATA)
