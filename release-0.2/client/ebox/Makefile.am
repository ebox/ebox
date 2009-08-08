## Process this file with automake to produce Makefile.in

SUBDIRS = conf doc po schemas src tools www

MAINTAINERCLEANFILES = aclocal.m4 configure Makefile.in config.status \
  config.log config/mkinstalldirs depcomp config/install-sh config/missing \
  config/config.guess config/config.sub

install-data-hook:
	mkdir -p @LOCALSTATEDIR@/ebox/tmp @LOCALSTATEDIR@/ebox/log
