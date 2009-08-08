AC_INIT([EBox], [0.1])

AC_CONFIG_AUX_DIR([config])
AC_CONFIG_SRCDIR([src/EBox/Module.pm])

AM_INIT_AUTOMAKE([foreign 1.8])

AM_MAINTAINER_MODE

AC_DEFINE_DIR(DATADIR, datadir)
AC_DEFINE_DIR(SYSCONFDIR, sysconfdir)
AC_DEFINE_DIR(LOCALSTATEDIR, localstatedir)
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
AC_SUBST(perlpath)

AC_DEFINE_DIR(PERLPATH, perlpath)

AC_PROG_PERL_MODULES(Log::Dispatch, ,
  AC_MSG_ERROR(Missing Log::Dispatch))

AC_PROG_PERL_MODULES(Log::Log4perl, ,
  AC_MSG_ERROR(Missing Log::Log4perl))

AC_PROG_PERL_MODULES(HTML::Template, ,
  AC_MSG_ERROR(Missing HTML::Template))

AC_PROG_PERL_MODULES(HTML::Template::Expr, ,
  AC_MSG_ERROR(Missing HTML::Template::Expr))

AC_PROG_PERL_MODULES(Locale::gettext, ,
  AC_MSG_ERROR(Missing Locale::gettext))

AC_PROG_PERL_MODULES(Locale::TextDomain, ,
  AC_MSG_ERROR(Missing Locale::TextDomain))

AC_PROG_PERL_MODULES(XML::Xerces, ,
  AC_MSG_ERROR(Missing XML::Xerces))

AC_PROG_PERL_MODULES(XML::Simple, ,
  AC_MSG_ERROR(Missing XML::Simple))

AC_PROG_PERL_MODULES(XML::XPath, ,
  AC_MSG_ERROR(Missing XML::XPath))

AC_PROG_PERL_MODULES(XML::XPath::XMLParser, ,
  AC_MSG_ERROR(Missing XML::XPath::XMLParser))

AC_PROG_PERL_MODULES(Net::Ifconfig::Wrapper, ,
  AC_MSG_ERROR(Missing Net::Ifconfig::Wrapper))

AC_PROG_PERL_MODULES(Net::IPv4Addr, ,
  AC_MSG_ERROR(Missing Net::IPv4Addr))

AC_PROG_PERL_MODULES(Sys::Hostname, ,
  AC_MSG_ERROR(Missing Sys::Hostname))

AC_PROG_PERL_MODULES(Sys::Load, ,
  AC_MSG_ERROR(Missing Sys::Load))

AC_PROG_PERL_MODULES(Sys::CPU, ,
  AC_MSG_ERROR(Missing Sys::CPU))

AC_PROG_PERL_MODULES(Error, ,
  AC_MSG_ERROR(Missing Error))
  
AC_PROG_PERL_MODULES(Devel::StackTrace, ,
  AC_MSG_ERROR(Missing Devel::StackTrace))
  
AC_PROG_PERL_MODULES(Apache::Singleton, ,
  AC_MSG_ERROR(Missing Apache::Singleton))
  
AC_PROG_PERL_MODULES(Apache::AuthCookie, ,
  AC_MSG_ERROR(Missing Apache::AuthCookie))
  
AC_PROG_APACHE
AC_MSG_NOTICE(Configuration files for apache will be installed in $HTTPCONFDIR/conf.d)

AM_PO_SUBDIRS

AC_CONFIG_FILES([
tools/Makefile
doc/coding/Makefile
doc/security/Makefile
doc/error/Makefile
doc/Makefile
src/cgi/Makefile
src/Makefile
src/templates/objects/Makefile
src/templates/login/Makefile
src/templates/logout/Makefile
src/templates/network/Makefile
src/templates/firewall/Makefile
src/templates/Makefile
src/EBox/Makefile
src/EBox/Exceptions/Makefile
src/EBox/CGI/Makefile
src/EBox/CGI/Objects/Makefile
src/EBox/CGI/Login/Makefile
src/EBox/CGI/Logout/Makefile
src/EBox/CGI/Summary/Makefile
src/EBox/CGI/Network/Makefile
src/EBox/CGI/Firewall/Makefile
src/EBox/Summary/Makefile
src/EBox/Config.pm
schemas/Makefile
conf/Makefile
conf/ebox.conf
conf/eboxlog.conf
conf/firewall.xml
conf/objects.xml
conf/network.xml
conf/global.xml
www/Makefile
Makefile
])

AC_CONFIG_FILES([po/Makefile], [AM_POSTPROCESS_PO_MAKEFILE])
AC_OUTPUT
