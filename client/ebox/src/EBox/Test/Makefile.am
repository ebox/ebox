## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox/Test

mods = Class.pm Composite.pm Model.pm Form.pm SubComposite.pm \
	StaticForm.pm

nobase_perl_DATA = $(mods)

SUBDIRS = t

SOURCES = $(nobase_perl_DATA)

EXTRA_DIST = $(mods)

MAINTAINERCLEANFILES = Makefile.in
