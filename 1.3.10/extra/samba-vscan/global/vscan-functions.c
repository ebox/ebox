/*
 * $Id: vscan-functions.c,v 1.7.2.2 2004/05/02 19:45:31 reniar Exp $
 * 
 * provides commonly used functions 
 *
 * Copyright (C) Rainer Link, 2002-2004
 *               OpenAntiVirus.org <rainer@openantivirus.org>
 *
 * This software is licensed under the GNU General Public License (GPL)
 * See: http://www.gnu.org/copyleft/gpl.html
 *
*/


#include "vscan-global.h"


/* taken from src/url.c of GNU wget */
/* Support for encoding and decoding of URL strings.  We determine
   whether a character is unsafe through static table lookup.  This
   code assumes ASCII character set and 8-bit chars.  */

enum {
  urlchr_reserved = 1,
  urlchr_unsafe   = 2
};
  
#define R  urlchr_reserved
#define U  urlchr_unsafe
#define RU R|U

#define urlchr_test(c, mask) (urlchr_table[(unsigned char)(c)] & (mask))

/* rfc1738 reserved chars, preserved from encoding.  */

#define RESERVED_CHAR(c) urlchr_test(c, urlchr_reserved)

/* rfc1738 unsafe chars, plus some more.  */

#define UNSAFE_CHAR(c) urlchr_test(c, urlchr_unsafe)

/* taken from src/wget.h of GNU wget */
/* Convert the ASCII character X to a hex-digit.  X should be between
   '0' and '9', or between 'A' and 'F', or between 'a' and 'f'.  The
   result is a number between 0 and 15.  If X is not a hexadecimal
   digit character, the result is undefined.  */
#define XCHAR_TO_XDIGIT(x)                      \
  (((x) >= '0' && (x) <= '9') ?                 \
   ((x) - '0') : (TOUPPER(x) - 'A' + 10))

/* The reverse of the above: convert a HEX digit in the [0, 15] range
   to an ASCII character representing it.  The A-F characters are
   always in upper case.  */
#define XDIGIT_TO_XCHAR(x) (((x) < 10) ? ((x) + '0') : ((x) - 10 + 'A'))


const static unsigned char urlchr_table[256] =
{
  U,  U,  U,  U,   U,  U,  U,  U,   /* NUL SOH STX ETX  EOT ENQ ACK BEL */
  U,  U,  U,  U,   U,  U,  U,  U,   /* BS  HT  LF  VT   FF  CR  SO  SI  */
  U,  U,  U,  U,   U,  U,  U,  U,   /* DLE DC1 DC2 DC3  DC4 NAK SYN ETB */
  U,  U,  U,  U,   U,  U,  U,  U,   /* CAN EM  SUB ESC  FS  GS  RS  US  */
  U,  0,  U, RU,   0,  U,  R,  0,   /* SP  !   "   #    $   %   &   '   */
  0,  0,  0,  R,   0,  0,  0,  R,   /* (   )   *   +    ,   -   .   /   */
  0,  0,  0,  0,   0,  0,  0,  0,   /* 0   1   2   3    4   5   6   7   */
  0,  0, RU,  R,   U,  R,  U,  R,   /* 8   9   :   ;    <   =   >   ?   */
 RU,  0,  0,  0,   0,  0,  0,  0,   /* @   A   B   C    D   E   F   G   */
  0,  0,  0,  0,   0,  0,  0,  0,   /* H   I   J   K    L   M   N   O   */
  0,  0,  0,  0,   0,  0,  0,  0,   /* P   Q   R   S    T   U   V   W   */
  0,  0,  0,  U,   U,  U,  U,  0,   /* X   Y   Z   [    \   ]   ^   _   */
  U,  0,  0,  0,   0,  0,  0,  0,   /* `   a   b   c    d   e   f   g   */
  0,  0,  0,  0,   0,  0,  0,  0,   /* h   i   j   k    l   m   n   o   */
  0,  0,  0,  0,   0,  0,  0,  0,   /* p   q   r   s    t   u   v   w   */
  0,  0,  0,  U,   U,  U,  U,  U,   /* x   y   z   {    |   }   ~   DEL */

  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,

  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
  U, U, U, U,  U, U, U, U,  U, U, U, U,  U, U, U, U,
};



BOOL set_boolean(BOOL *b, const char *value)
{

        BOOL retval;

        retval = True;

        if ( StrCaseCmp("yes", value) == 0 ||
             StrCaseCmp("true", value) == 0 ||
             StrCaseCmp("1", value) == 0 )
                *b = True;
        else if ( StrCaseCmp("no", value) == 0 ||
                  StrCaseCmp("false", value) == 0 ||
                  StrCaseCmp("0", value) == 0 )
                *b = False;
        else {
                DEBUG(2, ("samba-vscan: badly formed boolean in configuration file, parameter %s\n", value));
                retval = False;
        }

        return retval;
}

/* print a message via syslog */
void vscan_syslog(const char *printMessage, ...)
{
        char printMsg[512];

        va_list argptr;
        va_start(argptr, printMessage);
        vsnprintf(printMsg, sizeof(printMsg)-1, printMessage, argptr);
        va_end(argptr);

	syslog(SYSLOG_PRIORITY, "%s", printMsg);
}


/* print a message via syslog */
void vscan_syslog_alert(const char *printMessage, ...)
{
        char printMsg[512];

        va_list argptr;
        va_start(argptr, printMessage);
        vsnprintf(printMsg, sizeof(printMsg)-1, printMessage, argptr);
        va_end(argptr);

        syslog(SYSLOG_PRIORITY_ALERT, "%s", printMsg);
}


char* encode_string (const char *s)
{
  const char *p1;
  char *p2, *newstr;
  size_t newlen;
  size_t addition = 0;

 if ( strlen(s) - 1  > MAX_ENC_LENGTH_STR ) /* avoid integer overflow */
   return strdup(s);


  for (p1 = s; *p1; p1++)
    if (UNSAFE_CHAR (*p1))
      addition += 2;            /* Two more characters (hex digits) */

  if (!addition)
    return strdup(s);

  newlen = (p1 - s) + addition;
  if ( newlen <= 0 )     /* uhm, sth went wrong, return unencode string */
       return strdup(s);

  newstr = (char *)malloc (newlen + 1);
  if ( newstr == NULL )        /* not enough memory, return unencode string */
                return strdup(s);

  p1 = s;
  p2 = newstr;
  while (*p1)
    {
      if (UNSAFE_CHAR (*p1))
        {
          unsigned char c = *p1++;
          *p2++ = '%';
          *p2++ = XDIGIT_TO_XCHAR (c >> 4);
          *p2++ = XDIGIT_TO_XCHAR (c & 0xf);
        }
      else
        *p2++ = *p1++;
    }
  *p2 = '\0';
/*  assert (p2 - newstr == newlen); */

  return newstr;
}


int vscan_inet_socket_init(const char* daemon_name, const char* ip, const unsigned short int port)
{
        int sockfd;
        struct sockaddr_in servaddr;

        /* create socket */
        if (( sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0 ) {
               vscan_syslog("ERROR: can not create socket!\n");
               return -1;
        }

        bzero(&servaddr, sizeof(servaddr));
        servaddr.sin_family = AF_INET;
        servaddr.sin_port = htons(port);

        /* hm, inet_pton may not exist on all systems - FIXME ! */
        if ( inet_pton(AF_INET, ip, &servaddr.sin_addr) <= 0 ) {
                vscan_syslog("ERROR: inet_pton failed!\n");
                return -1;
        }

        /* connect to socket */
        if ( connect(sockfd, (struct sockaddr *) &servaddr, sizeof(servaddr)) < 0 )
        {
                vscan_syslog("ERROR: can not connect to %s (IP: '%s', port: '%d')!\n", daemon_name, ip, port);
                return -1;
        }


        return sockfd;

}

int vscan_unix_socket_init(const char* daemon_name, const char* socket_name)
{

        int sockfd;
        struct sockaddr_un servaddr;

        /* create socket */
        if (( sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) < 0 ) {
               vscan_syslog("ERROR: can not create socket!");
               return -1;
        }

        bzero(&servaddr, sizeof(servaddr));
        servaddr.sun_family = AF_UNIX;
        safe_strcpy(servaddr.sun_path, socket_name, sizeof(servaddr.sun_path)-1);

        /* connect to socket */
        if ( connect(sockfd, (struct sockaddr *) &servaddr, sizeof(servaddr)) < 0 ) {
                vscan_syslog("ERROR: can not connect to %s (socket: '%s')!", daemon_name, socket_name);
                return -1;
        }

    return sockfd;

}


void vscan_socket_end(int sockfd)
{
        /* sockfd == -1 indicates an error while connecting to socket */
        if ( sockfd >= 0 ) {
                close(sockfd);
        }

}

