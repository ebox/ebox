AC_INIT([EBox-usersandgroups], [0.1-SVN])

AC_CONFIG_AUX_DIR([config])
AC_CONFIG_SRCDIR([src/EBox/UsersAndGroups.pm])

AM_INIT_AUTOMAKE([foreign])

AM_MAINTAINER_MODE

AM_GNU_GETTEXT

AC_DEFINE_DIR(LIBDIR, libdir)


AC_CHECK_PROG(PERL, perl, perl, none)

if test "$PERL" = "none" ; then
	AC_MSG_ERROR(perl not found)
fi

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

AC_PROG_PERL_MODULES(Net::LDAP, ,
	AC_MSG_ERROR(Missing Net::LDAP))

AC_PROG_PERL_MODULES(Net::LDAP::Constant, ,
	AC_MSG_ERROR(Missing Net::LDAP::Constant))

AC_PROG_PERL_MODULES(Net::LDAP::LDIF, ,
	AC_MSG_ERROR(Missing Net::LDAP::LDIF))

AC_CONF_EBOX

# FIXME Install preset slapd.conf 
#AC_PROG_SQUID
#AC_MSG_NOTICE(Configuration file for squid will be installed in $SQUIDCONF)

AC_OUTPUT([
src/Makefile
src/EBox/Makefile
src/EBox/CGI/Makefile
src/templates/Makefile
Makefile
])
