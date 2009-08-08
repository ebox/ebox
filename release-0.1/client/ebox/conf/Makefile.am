## Process this file with automake to produce Makefile.in

Xmldir = $(localstatedir)/ebox/conf
Xml_DATA = objects.xml firewall.xml network.xml global.xml eboxlog.conf

Passwddir = $(localstatedir)/ebox/conf
Passwd_DATA = ebox.passwd

Apachedir = @HTTPCONFDIR@/conf.d
Apache_DATA = ebox.conf

EXTRA_DIST = $(Xml_DATA) $(Passwd_DATA)

MAINTAINERCLEANFILES = Makefile.in ebox.conf
