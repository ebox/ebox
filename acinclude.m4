dnl Available from the GNU Autoconf Macro Archive at:
dnl http://www.gnu.org/software/ac-archive/htmldoc/ac_define_dir.html
dnl
AC_DEFUN([AC_DEFINE_DIR], [
  test "x$prefix" = xNONE && prefix="$ac_default_prefix"
  test "x$exec_prefix" = xNONE && exec_prefix='${prefix}'
  ac_define_dir=`eval echo [$]$2`
  ac_define_dir=`eval echo [$]ac_define_dir`
  $1="$ac_define_dir"
  AC_SUBST($1)
  ifelse($3, ,
    AC_DEFINE_UNQUOTED($1, "$ac_define_dir"),
    AC_DEFINE_UNQUOTED($1, "$ac_define_dir", $3))
])
AC_DEFUN([AC_CONF_EBOX],
#
# Handle user hints
#
[
  AC_MSG_CHECKING(conf path)
  CONFPATH=`perl -MEBox::Config -e 'print EBox::Config->conf'`
  if test -z "$CONFPATH"; then
  	AC_MSG_ERROR("conf  path  not found")
  fi
  AC_SUBST(CONFPATH)
  AC_MSG_RESULT($CONFPATH)
  
  AC_MSG_CHECKING(stubs path)
  STUBSPATH=`perl -MEBox::Config -e 'print EBox::Config->stubs'`
  if test -z "$STUBSPATH"; then
  	AC_MSG_ERROR("stubs  path  not found")
  fi
  AC_SUBST(STUBSPATH)
  AC_MSG_RESULT($STUBSPATH)

  AC_MSG_CHECKING(cgi path)
  CGIPATH=`perl -MEBox::Config -e 'print EBox::Config->cgi'`
  if test -z "$CGIPATH"; then
  	AC_MSG_ERROR("ebox cgi path not found")
  fi
  AC_SUBST(CGIPATH)
  AC_MSG_RESULT($CGIPATH)
  
  AC_MSG_CHECKING(templates path)
  TEMPLATESPATH=`perl -MEBox::Config -e 'print EBox::Config->templates'`
  if test -z "$CGIPATH"; then
  	AC_MSG_ERROR("ebox template path  not found")
  fi
  AC_SUBST(TEMPLATESPATH)
  AC_MSG_RESULT($TEMPLATESPATH)
  
  AC_MSG_CHECKING(schemas path)
  SCHEMASPATH=`perl -MEBox::Config -e 'print EBox::Config->schemas'`
  if test -z "$CGIPATH"; then
  	AC_MSG_ERROR("ebox schemas path  not found")
  fi
  AC_SUBST(SCHEMASPATH)
  AC_MSG_RESULT($SCHEMASPATH)
  
  AC_MSG_CHECKING(www path)
  WWWPATH=`perl -MEBox::Config -e 'print EBox::Config->www'`
  if test -z "$CGIPATH"; then
  	AC_MSG_ERROR("ebox www path  not found")
  fi
  AC_SUBST(WWWPATH)
  AC_MSG_RESULT($WWWPATH)
  
  AC_MSG_CHECKING(css path)
  CSSPATH=`perl -MEBox::Config -e 'print EBox::Config->css'`
  if test -z "$CGIPATH"; then
  	AC_MSG_ERROR("ebox css path  not found")
  fi
  AC_SUBST(CSSPATH)
  AC_MSG_RESULT($CSSPATH)
  
  AC_MSG_CHECKING(images path)
  IMAGESPATH=`perl -MEBox::Config -e 'print EBox::Config->images'`
  if test -z "$CGIPATH"; then
  	AC_MSG_ERROR("ebox images path  not found")
  fi
  AC_SUBST(IMAGESPATH)
  AC_MSG_RESULT($IMAGESPATH)

])
dnl Based on:
dnl http://www.gnu.org/software/ac-archive/htmldoc/ac_prog_apache.html
dnl Heavily modified for Ebox.
AC_DEFUN([AC_PROG_SQUID],
#
# Handle user hints
#
[
  if test -z "$SQUIDPATH"; then
    AC_PATH_PROG(SQUID, squid, , /usr/local/squid/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/opt/squid/bin:/opt/squid/sbin:/opt/squid/bin:/opt/squid/sbin)
  else 
    AC_PATH_PROG(SQUID, squid, , $SQUIDPATH)
  fi
  AC_SUBST(SQUID)
  if test -z "$SQUID" ; then
      AC_MSG_ERROR("squid executable not found");
  fi
  #
  # Collect apache version number. If for nothing else, this
  # guaranties that httpd is a working apache executable.
  #
  SQUID_READABLE_VERSION=`$SQUID -v | grep 'Version' | sed -e 's/Squid.*Version *//'`
  SQUID_VERSION=`echo $SQUID_READABLE_VERSION | sed -e 's/\.//g'`
  if test -z "$SQUID_VERSION" ; then
      AC_MSG_ERROR("could not determine squid version number");
  fi
  #
  # Find configuration directory
  #
  changequote(<<, >>)dnl
  SQUIDCONF=`$SQUID -v | grep ^configure |  sed -e 's/.*sysconfdir=\([^ ]*\).*/\1/'`
  changequote([, ])dnl
  SQUIDCONF="$SQUIDCONF/squid.conf"
  AC_MSG_CHECKING(squid.conf)
  if test -f "$SQUIDCONF"
  then
    AC_MSG_RESULT(in $SQUIDCONF)
  else
    AC_MSG_ERROR(squid configuration directory not found)
  fi
  #SQUIDCONFDIR=`dirname $SQUIDCONF`
  AC_SUBST(SQUIDCONF)
  AC_PATH_PROG(SQUID_INIT, squid, , /etc/init.d)
  if test -z "$SQUID_INIT" ; then
  	AC_MSG_ERROR("squid init script not found")
  fi	
  AC_SUBST(SQUID_INIT)
])
dnl Available from the GNU Autoconf Macro Archive at:
dnl http://www.gnu.org/software/ac-archive/htmldoc/ac_prog_perl_modules.html
dnl
AC_DEFUN([AC_PROG_PERL_MODULES],[dnl
ac_perl_modules="$1"
# Make sure we have perl
if test -z "$PERL"; then
AC_CHECK_PROG(PERL,perl,perl)
fi

if test "x$PERL" != x; then
  ac_perl_modules_failed=0
  for ac_perl_module in $ac_perl_modules; do
    AC_MSG_CHECKING(for perl module $ac_perl_module)

    # Would be nice to log result here, but can't rely on autoconf internals
    $PERL "-M$ac_perl_module" -e exit > /dev/null 2>&1
    if test $? -ne 0; then
      AC_MSG_RESULT(no);
      ac_perl_modules_failed=1
   else
      AC_MSG_RESULT(ok);
    fi
  done

  # Run optional shell commands
  if test "$ac_perl_modules_failed" = 0; then
    :
    $2
  else
    :
    $3
  fi
else
  AC_MSG_WARN(could not find perl)
fi])dnl
