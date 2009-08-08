AC_INIT([EBox-squid], [0.2])

AC_CONFIG_AUX_DIR([config])
AC_CONFIG_SRCDIR([src/EBox/Squid.pm.in])

AM_INIT_AUTOMAKE([foreign])

AM_MAINTAINER_MODE


AC_DEFINE_DIR(LIBDIR, libdir)


AC_CHECK_PROG(PERL, perl, perl, none)
AC_CHECK_PROG(GCONFTOOL, gconftool-2, gconftool-2, none)

if test "$PERL" = "none" ; then
	AC_MSG_ERROR(perl not found)
fi
if test "$GCONFTOOL" = "none" ; then
	AC_MSG_ERROR(gconftool not found)
fi

AM_GCONF_SOURCE_2

perlpath=`$PERL -e 'foreach (@INC) { print "$_\n";}' | grep "^$LIBDIR" | head -1`
if test -z "$perlpath" ; then
perlpath=`$PERL -e 'foreach (@INC) { print "$_\n";}' | grep "^$prefix" | head -1`
fi
if test -z "$perlpath" ; then
perlpath="$DATADIR/perl5/"
AC_MSG_NOTICE([Perl libraries will be installed in $perlpath, make sure to
include it in your path])
else
AC_MSG_NOTICE([Perl libraries will be installed in $perlpath])
fi

AC_DEFINE_DIR(PERLPATH, perlpath)

AC_PROG_PERL_MODULES(HTML::Template, ,
  AC_MSG_ERROR(Missing HTML::Template))

AC_PROG_PERL_MODULES(HTML::Template::Expr, ,
  AC_MSG_ERROR(Missing HTML::Template::Expr))

AC_PROG_PERL_MODULES(Locale::gettext, ,
  AC_MSG_ERROR(Missing Locale::gettext))

AC_PROG_PERL_MODULES(Devel::StackTrace, ,
  AC_MSG_ERROR(Missing Devel::StackTrace))
 
AC_CONF_EBOX

AC_PROG_SQUID
AC_MSG_NOTICE(Configuration file for squid will be installed in $SQUIDCONF)

AM_PO_SUBDIRS

AC_CONFIG_FILES([
src/Makefile
src/EBox/Makefile
src/EBox/Squid.pm
src/EBox/CGI/Makefile
src/templates/Makefile
schemas/Makefile
stubs/Makefile
www/Makefile
Makefile
])

AC_CONFIG_FILES([po/Makefile], [AM_POSTPROCESS_PO_MAKEFILE])
AC_OUTPUT
