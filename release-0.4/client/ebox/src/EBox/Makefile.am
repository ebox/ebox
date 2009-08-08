## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox

mods = Module.pm Html.pm Validate.pm \
	Network.pm Global.pm Firewall.pm Iptables.pm Objects.pm \
	SysInfo.pm GConfModule.pm Gettext.pm \
	Sudo.pm Auth.pm Order.pm GConfHelper.pm \
	GConfState.pm GConfConfig.pm Apache.pm Backup.pm FirewallHelper.pm

nobase_perl_DATA = $(mods) Config.pm

SUBDIRS = CGI Exceptions Summary

SOURCES = $(nobase_perl_DATA)

EXTRA_DIST = $(mods)

DISTCLEANFILES = Config.pm

MAINTAINERCLEANFILES = Makefile.in
