## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox/Events/Model

SUBDIRS = Dispatcher t Watcher Report

mods = ConfigureEventDataTable.pm ConfigureDispatcherDataTable.pm \
	ConfigurationComposite.pm GeneralComposite.pm Fallback.pm

nobase_perl_DATA = $(mods)

SOURCES = $(nobase_perl_DATA)

EXTRA_DIST = $(mods)

MAINTAINERCLEANFILES = Makefile.in
