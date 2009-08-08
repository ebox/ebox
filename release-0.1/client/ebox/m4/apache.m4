dnl Based on:
dnl http://www.gnu.org/software/ac-archive/htmldoc/ac_prog_apache.html
dnl Heavily modified for Ebox.
AC_DEFUN([AC_PROG_APACHE],
#
# Handle user hints
#
[
  AC_PATH_PROG(APACHE, httpd, , /usr/local/apache/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/opt/httpd/bin:/opt/httpd/sbin:/opt/apache/bin:/opt/apache/sbin)
  if test -z "$APACHE" ; then
    AC_PATH_PROG(APACHE, apache, , /usr/local/apache/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/opt/httpd/bin:/opt/httpd/sbin:/opt/apache/bin:/opt/apache/sbin)
  fi
  AC_SUBST(APACHE)
  if test -z "$APACHE" ; then
      AC_MSG_ERROR("apache server executable not found");
  fi
  #
  # Collect apache version number. If for nothing else, this
  # guaranties that httpd is a working apache executable.
  #
  changequote(<<, >>)dnl
  APACHE_READABLE_VERSION=`$APACHE -v | grep 'Server version' | sed -e 's;.*Apache/\([0-9\.][0-9\.]*\).*;\1;'`
  changequote([, ])dnl
  APACHE_VERSION=`echo $APACHE_READABLE_VERSION | sed -e 's/\.//g'`
  if test -z "$APACHE_VERSION" ; then
      AC_MSG_ERROR("could not determine apache version number");
  fi
  #
  # Find configuration directory
  #
  HTTPCONF=`$APACHE -V | grep SERVER_CONFIG_FILE | sed -e 's/.*"\(.*\)"/\1/'`
  AC_MSG_CHECKING(httpd.conf)
  if test -f "$HTTPCONF"
  then
    AC_MSG_RESULT(in $HTTPCONF)
  else
    AC_MSG_ERROR(apache configuration directory not found)
  fi
  HTTPCONFDIR=`dirname $HTTPCONF`
  AC_SUBST(HTTPCONFDIR)
])
