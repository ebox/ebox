## Process this file with automake to produce Makefile.in

Etcdir = $(sysconfdir)/ebox
Etc_DATA = ebox.conf

Confdir = $(localstatedir)/lib/ebox/conf
Conf_DATA = eboxlog.conf

Passwddir = $(localstatedir)/lib/ebox/conf
Passwd_DATA = ebox.passwd

EXTRA_DIST = $(Passwd_DATA) $(Etc_DATA) ebox.cert ebox.key

MAINTAINERCLEANFILES = Makefile.in

DISTCLEANFILES = eboxlog.conf .gconf.path
