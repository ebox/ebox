package EBox::ThirdParty::Apache2::AuthCookie;

use strict;

use Carp;
use CGI '3.12';
use mod_perl2 '1.9922';

use EBox::ThirdParty::Apache2::AuthCookie::Util;
use Apache2::RequestRec;
use Apache2::RequestUtil;
use Apache2::Log;
use Apache2::Access;
use Apache2::Response;
use Apache2::Util;
use APR::Table;
use Apache2::Const qw(:common M_GET HTTP_FORBIDDEN HTTP_MOVED_TEMPORARILY);
use vars qw($VERSION);

# $Id: AuthCookie.pm 227 2008-04-16 14:59:56Z mschout $
$VERSION = '3.12';

sub recognize_user {
    my ($self, $r) = @_;

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    my $auth_type = $r->auth_type;
    my $auth_name = $r->auth_name;

    return DECLINED unless $auth_type and $auth_name;

    return DECLINED unless $r->headers_in->get('Cookie');

    my $cookie = $self->key($r);
    my $cookie_name = $self->cookie_name($r);

    $r->server->log_error("cookie $cookie_name is $cookie")
        if $debug >= 2;

    return DECLINED unless $cookie;

    my ($user,@args) = $auth_type->authen_ses_key($r, $cookie);

    if ($user and scalar @args == 0) {
        $r->server->log_error("user is $user") if $debug >= 2;

        # send cookie with update expires timestamp if session timeout is on
        if (my $expires = $r->dir_config("${auth_name}SessionTimeout")) {
            $self->send_cookie($r, $cookie, {expires => $expires});
        }

        $r->user($user);
    }
    elsif (scalar @args > 0 and $auth_type->can('custom_errors')) {
        return $auth_type->custom_errors($r, $user, @args);
    }

    return OK;
}

sub cookie_name {
    my ($self, $r) = @_;

    my $auth_type = $r->auth_type;
    my $auth_name = $r->auth_name;

    my $cookie_name = $r->dir_config("${auth_name}CookieName") ||
                      "${auth_type}_${auth_name}";

    return $cookie_name;
}

sub handle_cache {
    my ($self, $r) = @_;

    my $auth_name = $r->auth_name;

    return unless $auth_name;

    unless ($r->dir_config("${auth_name}Cache")) {
        $r->no_cache(1);
        $r->err_headers_out->set(Pragma => 'no-cache');
    }
}

sub remove_cookie {
    my ($self, $r) = @_;

    my $cookie_name = $self->cookie_name($r);

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    my $str = $self->cookie_string(
        request => $r,
        key     => $cookie_name,
        value   => '',
        expires => 'Mon, 21-May-1971 00:00:00 GMT'
    );

    $r->err_headers_out->add("Set-Cookie" => "$str");
    $r->server->log_error("removed_cookie ".
                          $r->err_headers_out->get("Set-Cookie"))
        if $debug >= 2;
}

# convert current request to GET
sub _convert_to_get {
    my ($self, $r, $args) = @_;

    return unless $r->method eq 'POST';

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    $r->server->log_error("Converting POST -> GET") if $debug >= 2;

    my @pairs =();
    while (my ($name, $value) = each %$args) {
        # we dont want to copy login data, only extra data
        next if $name eq 'destination'
             or $name =~ /^credential_\d+$/;

        $value = '' unless defined $value;
        for my $v (split /\0/, $value) {
            push @pairs, escape_uri($r, $name) . '=' . escape_uri($r, $v);
        }
    }

    $r->args(join '&', @pairs) if scalar(@pairs) > 0;

    $r->method('GET');
    $r->method_number(M_GET);
    $r->headers_in->unset('Content-Length');
}

sub escape_uri {
    my ($r, $string) = @_;
    return EBox::ThirdParty::Apache2::AuthCookie::Util::escape_path($string, $r->pool);
}

# get GET or POST data and return hash containing the data.
sub _get_form_data {
    my ($self, $r) = @_;

    my $data = '';

    my $cgi = CGI->new($r);

    return $cgi->Vars();
}

sub login {
    my ($self, $r) = @_;

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    my $auth_type = $r->auth_type;
    my $auth_name = $r->auth_name;

    my %args = $self->_get_form_data($r);

    if ($r->method eq 'POST') {
        $self->_convert_to_get($r, \%args);
    }

    unless (exists $args{'destination'}) {
        $r->server->log_error("No key 'destination' found in form data");
        $r->subprocess_env('AuthCookieReason', 'no_cookie');
        return $auth_type->login_form($r);
    }

    # Get the credentials from the data posted by the client
    my @credentials;
    for (my $i = 0; exists $args{"credential_$i"}; $i++) {
        my $key = "credential_$i";
        $r->server->log_error("$key $args{$key}") if $debug >= 2;
        push @credentials, $args{$key};
    }

    # save creds in pnotes so login form script can use them if it wants to
    $r->pnotes("${auth_name}Creds", \@credentials);

    # Exchange the credentials for a session key.
    my $ses_key = $self->authen_cred($r, @credentials);
    unless ($ses_key) {
        $r->server->log_error("Bad credentials") if $debug >= 2;
        $r->subprocess_env('AuthCookieReason', 'bad_credentials');
        $r->uri($args{'destination'});
        return $auth_type->login_form($r);
    }

    if ($debug >= 2) {
        defined $ses_key ? $r->server->log_error("ses_key $ses_key")
                         : $r->server->log_error("ses_key undefined");
    }

    $self->send_cookie($r, $ses_key);

    $self->handle_cache($r);

    if ($debug >= 2) {
        $r->server->log_error("redirect to $args{destination}");
    }

    $r->headers_out->set(
        "Location" => $self->untaint_destination($args{'destination'}));

    return HTTP_MOVED_TEMPORARILY;
}

sub untaint_destination {
    my ($self, $dest) = @_;

    return EBox::ThirdParty::Apache2::AuthCookie::Util::escape_destination($dest);
}

sub logout {
    my ($self,$r) = @_;

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    $self->remove_cookie($r);

    $self->handle_cache($r);
}

sub authenticate {
    my ($auth_type, $r) = @_;

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    $r->server->log_error("auth_type " . $auth_type) if ($debug >= 3);

    unless ($r->is_initial_req) {
        if (defined $r->prev) {
            # we are in a subrequest.  Just copy user from previous request.
            $r->user( $r->prev->user );
        }
        return OK;
    }

    if ($debug >= 3) {
        $r->server->log_error("r=$r authtype=". $r->auth_type);
    }

    if ($r->auth_type ne $auth_type) {
        # This location requires authentication because we are being called,
        # but we don't handle this AuthType.
        $r->server->log_error("AuthType mismatch: $auth_type =/= ".$r->auth_type) if $debug >= 3;
        return DECLINED;
    }

    # Ok, the AuthType is $auth_type which we handle, what's the authentication
    # realm's name?
    my $auth_name = $r->auth_name;
    $r->server->log_error("auth_name $auth_name") if $debug >= 2;
    unless ($auth_name) {
        $r->server->log_error("AuthName not set, AuthType=$auth_type", $r->uri);
        return SERVER_ERROR;
    }

    # Get the Cookie header. If there is a session key for this realm, strip
    # off everything but the value of the cookie.
    my $ses_key_cookie = $auth_type->key($r) || '';

    $r->server->log_error("ses_key_cookie " . $ses_key_cookie) if $debug >= 1;
    $r->server->log_error("uri " . $r->uri) if $debug >= 2;

    if ($ses_key_cookie) {
        my ($auth_user, @args) = $auth_type->authen_ses_key($r, $ses_key_cookie);

        if ($auth_user and scalar @args == 0) {
            # We have a valid session key, so we return with an OK value.
            # Tell the rest of Apache what the authentication method and
            # user is.

            $r->ap_auth_type($auth_type);
            $r->user($auth_user);
            $r->server->log_error("user authenticated as $auth_user")
                if $debug >= 1;

            # send new cookie if SessionTimeout is on
            if (my $expires = $r->dir_config("${auth_name}SessionTimeout")) {
                $auth_type->send_cookie($r, $ses_key_cookie,
                                        {expires => $expires});
            }

            return OK;
        }
        elsif (scalar @args > 0 and $auth_type->can('custom_errors')) {
            return $auth_type->custom_errors($r, $auth_user, @args);
        }
        else {
            # There was a session key set, but it's invalid for some reason. So,
            # remove it from the client now so when the credential data is posted
            # we act just like it's a new session starting.
            $auth_type->remove_cookie($r);
            $r->subprocess_env('AuthCookieReason', 'bad_cookie');
        }
    }
    else {
        $r->subprocess_env('AuthCookieReason', 'no_cookie');
    }

    # This request is not authenticated, but tried to get a protected
    # document.  Send client the authen form.
    return $auth_type->login_form($r);
}

sub login_form {
    my ($self, $r) = @_;

    my $auth_name = $r->auth_name;

    my %args = $self->_get_form_data($r);

    if ($r->method eq 'POST') {
        $self->_convert_to_get($r, \%args);
    }

    # There should be a PerlSetVar directive that gives us the URI of
    # the script to execute for the login form.

    my $authen_script;
    unless ($authen_script = $r->dir_config($auth_name . "LoginScript")) {
        $r->server->log_error("PerlSetVar '${auth_name}LoginScript' not set", $r->uri);
        return SERVER_ERROR;
    }

    $r->custom_response(HTTP_FORBIDDEN, $authen_script);

    return HTTP_FORBIDDEN;
}

sub satisfy_is_valid {
    my ($auth_type, $r, $satisfy) = @_;

    $satisfy = lc $satisfy;

    if ($satisfy eq 'any' or $satisfy eq 'all') {
        return 1;
    }
    else {
        my $auth_name = $r->auth_name;
        $r->server->log_error("PerlSetVar ${auth_name}Satisfy $satisfy invalid",$r->uri);
        return 0;
    }
}

sub get_satisfy {
    my ($auth_type, $r) = @_;

    my $auth_name = $r->auth_name;

    return lc $r->dir_config("${auth_name}Satisfy") || 'all';
}

sub authorize {
    my ($auth_type, $r) = @_;

    my $debug = $r->dir_config("AuthCookieDebug") || 0;

    $r->server->log_error('authorize() for '.$r->uri()) if $debug >= 3;

    return OK unless $r->is_initial_req; #only the first internal request

    if ($r->auth_type ne $auth_type) {
        $r->server->log_error("auth type mismatch $auth_type != ".$r->auth_type)
            if $debug >= 3;
        return DECLINED;
    }

    my $reqs_arr = $r->requires or return DECLINED;

    my $user = $r->user;

    $r->server->log_error("authorize user=$user type=$auth_type") if $debug >=3;

    unless ($user) {
        # user is either undef or =0 which means the authentication failed
        $r->server->log_error("No user authenticated", $r->uri);
        return HTTP_FORBIDDEN;
    }

    my $satisfy = $auth_type->get_satisfy($r);
    return SERVER_ERROR unless $auth_type->satisfy_is_valid($r,$satisfy);
    my $satisfy_all = $satisfy eq 'all';

    my ($forbidden);
    foreach my $req (@$reqs_arr) {
        my ($requirement, $args) = split /\s+/, $req->{requirement}, 2;
        $args = '' unless defined $args;
        $r->server->log_error("requirement := $requirement, $args") if $debug >= 2;

        if (lc($requirement) eq 'valid-user') {
            if ($satisfy_all) {
                next;
            }
            else {
                return OK;
            }
        }

        if ($requirement eq 'user') {
            if ($args =~ m/\b$user\b/) {
                next if $satisfy_all;
                return OK; # satisfy any
            }

            $forbidden = 1;
            next;
        }

        # Call a custom method
        my $ret_val = $auth_type->$requirement($r, $args);
        $r->server->log_error("$auth_type->$requirement returned $ret_val") if $debug >= 3;
        if ($ret_val == OK) {
            next if $satisfy_all;
            return OK; # satisfy any
        }

        # Nothing succeeded, deny access to this user.
        $forbidden = 1;
    }

    return $forbidden ? HTTP_FORBIDDEN : OK;
}

sub send_cookie {
    my ($self, $r, $ses_key, $cookie_args) = @_;

    $cookie_args = {} unless defined $cookie_args;

    my $cookie_name = $self->cookie_name($r);

    my $cookie = $self->cookie_string(
        request => $r,
        key     => $cookie_name,
        value   => $ses_key,
        %$cookie_args
    );

    my $auth_name = $r->auth_name;

    # add a P3P header if user has configured it.
    if (my $p3p = $r->dir_config("${auth_name}P3P")) {
        $r->err_headers_out->set(P3P => $p3p);
    }

    $r->err_headers_out->add("Set-Cookie" => $cookie);
}


# cookie_string takes named parameters:
#    request
#    key
#    value
#    expires
# 
sub cookie_string {
    my $self = shift;
    my %p = @_;
    for (qw/request key/) {
        croak "missing required parameter $_" unless defined $p{$_};
    }
    # its okay if value is undef here.

    my $r = $p{request};

    $p{value} = '' unless defined $p{value};

    my $string = sprintf '%s=%s', @p{'key','value'};

    my $auth_name = $r->auth_name;

    if (my $expires = $p{expires} || $r->dir_config("${auth_name}Expires")) {
        $expires = EBox::ThirdParty::Apache2::AuthCookie::Util::expires($expires);
        $string .= "; expires=$expires";
    }

    $string .= '; path=' . ( $self->get_cookie_path($r) || '/' );

    if (my $domain = $r->dir_config("${auth_name}Domain")) {
        $string .= "; domain=$domain";
    }

    if ($r->dir_config("${auth_name}Secure")) {
        $string .= '; secure';
    }

    # HttpOnly is an MS extension.  See
    # http://msdn.microsoft.com/workshop/author/dhtml/httponly_cookies.asp
    if ($r->dir_config("${auth_name}HttpOnly")) {
        $string .= '; HttpOnly';
    }

    return $string;
}

sub key {
    my ($self, $r) = @_;

    my $cookie_name = $self->cookie_name($r);

    my $allcook = ($r->headers_in->get("Cookie") || "");

    return ($allcook =~ /(?:^|\s)$cookie_name=([^;]*)/)[0];
}

sub get_cookie_path {
    my ($self, $r) = @_;

    my $auth_name = $r->auth_name;

    return $r->dir_config("${auth_name}Path");
}

1;

__END__

=head1 NAME

Apache2::AuthCookie - Perl Authentication and Authorization via cookies

=head1 SYNOPSIS

Make sure your mod_perl is at least 1.24, with StackedHandlers,
MethodHandlers, Authen, and Authz compiled in.

 # In httpd.conf or .htaccess:
 PerlModule Sample::AuthCookieHandler
 PerlSetVar WhatEverPath /
 PerlSetVar WhatEverLoginScript /login.pl

 # use to alter how "require" directives are matched. Can be "Any" or "All".
 # If its "Any", then you must only match Any of the "require" directives. If
 # its "All", then you must match All of the require directives. 
 #
 # Default: All
 PerlSetVar WhatEverSatisfy Any
 
 # The following line is optional - it allows you to set the domain
 # scope of your cookie.  Default is the current domain.
 PerlSetVar WhatEverDomain .yourdomain.com

 # Use this to only send over a secure connection
 PerlSetVar WhatEverSecure 1

 # Use this if you want user session cookies to expire if the user
 # doesn't request a auth-required or recognize_user page for some
 # time period.  If set, a new cookie (with updated expire time)
 # is set on every request.
 PerlSetVar WhatEverSessionTimeout +30m

 # to enable the HttpOnly cookie property, use HttpOnly.
 # this is an MS extension.  See:
 # http://msdn.microsoft.com/workshop/author/dhtml/httponly_cookies.asp
 PerlSetVar WhatEverHttpOnly 1

 # Usually documents are uncached - turn off here
 PerlSetVar WhatEverCache 1

 # Use this to make your cookies persistent (+2 hours here)
 PerlSetVar WhatEverExpires +2h

 # Use to make AuthCookie send a P3P header with the cookie
 # see http://www.w3.org/P3P/ for details about what the value 
 # of this should be
 PerlSetVar WhatEverP3P "CP=\"...\""

 # These documents require user to be logged in.
 <Location /protected>
  AuthType Sample::AuthCookieHandler
  AuthName WhatEver
  PerlAuthenHandler Sample::AuthCookieHandler->authenticate
  PerlAuthzHandler Sample::AuthCookieHandler->authorize
  require valid-user
 </Location>

 # These documents don't require logging in, but allow it.
 <FilesMatch "\.ok$">
  AuthType Sample::AuthCookieHandler
  AuthName WhatEver
  PerlFixupHandler Sample::AuthCookieHandler->recognize_user
 </FilesMatch>

 # This is the action of the login.pl script above.
 <Files LOGIN>
  AuthType Sample::AuthCookieHandler
  AuthName WhatEver
  SetHandler perl-script
  PerlResponseHandler Sample::AuthCookieHandler->login
 </Files>

=head1 DESCRIPTION

WARNING! This is an early version of B<Apache::AuthCookie> for mod_perl version
2.  If you are running under mod_perl version 2, this module should be
considered of beta quality.  If you are a subclass author and would like to see
additional changes (besides those listed in README.modperl2) to the interface
provided by this module under mod_perl version 2, please contact me at
mschout@gkg.net.  The interface for mod_perl version 1 has not changed.

B<Apache::AuthCookie> allows you to intercept a user's first
unauthenticated access to a protected document. The user will be
presented with a custom form where they can enter authentication
credentials. The credentials are posted to the server where AuthCookie
verifies them and returns a session key.

The session key is returned to the user's browser as a cookie. As a
cookie, the browser will pass the session key on every subsequent
accesses. AuthCookie will verify the session key and re-authenticate
the user.

All you have to do is write a custom module that inherits from
AuthCookie.  Your module is a class which implements two methods:

=over 4

=item C<authen_cred()>

Verify the user-supplied credentials and return a session key.  The
session key can be any string - often you'll use some string
containing username, timeout info, and any other information you need
to determine access to documents, and append a one-way hash of those
values together with some secret key.

=item C<authen_ses_key()>

Verify the session key (previously generated by C<authen_cred()>,
possibly during a previous request) and return the user ID.  This user
ID will be fed to C<$r-E<gt>user()> to set Apache's idea of who's logged in.

=back

By using AuthCookie versus Apache's built-in AuthBasic you can design
your own authentication system.  There are several benefits.

=over 4

=item 1.

The client doesn't *have* to pass the user credentials on every
subsequent access.  If you're using passwords, this means that the
password can be sent on the first request only, and subsequent
requests don't need to send this (potentially sensitive) information.
This is known as "ticket-based" authentication.

=item 2.

When you determine that the client should stop using the
credentials/session key, the server can tell the client to delete the
cookie.  Letting users "log out" is a notoriously impossible-to-solve
problem of AuthBasic.

=item 3.

AuthBasic dialog boxes are ugly.  You can design your own HTML login
forms when you use AuthCookie.

=item 4.

You can specify the domain of a cookie using PerlSetVar commands.  For
instance, if your AuthName is C<WhatEver>, you can put the command 

 PerlSetVar WhatEverDomain .yourhost.com

into your server setup file and your access cookies will span all
hosts ending in C<.yourhost.com>.

=item 5.

You can optionally specify the name of your cookie using the C<CookieName>
directive.  For instance, if your AuthName is C<WhatEver>, you can put the
command

 PerlSetVar WhatEverCookieName MyCustomName

into your server setup file and your cookies for this AuthCookie realm will be
named MyCustomName.  Default is AuthType_AuthName.

=item 6.

By default users must satisfy ALL of the C<require> directives.  If you
want authentication to succeed if ANY C<require> directives are met, use the
C<Satisfy> directive.  For instance, if your AuthName is C<WhatEver>, you can
put the command

 PerlSetVar WhatEverSatisfy Any

into your server startup file and authentication for this realm will succeed if
ANY of the C<require> directives are met.

=back

This is the flow of the authentication handler, less the details of the
redirects. Two HTTP_MOVED_TEMPORARILY's are used to keep the client from
displaying the user's credentials in the Location field. They don't really
change AuthCookie's model, but they do add another round-trip request to the
client.

=for html
<PRE>

 (-----------------------)     +---------------------------------+
 ( Request a protected   )     | AuthCookie sets custom error    |
 ( page, but user hasn't )---->| document and returns            |
 ( authenticated (no     )     | HTTP_FORBIDDEN. Apache abandons |      
 ( session key cookie)   )     | current request and creates sub |      
 (-----------------------)     | request for the error document. |<-+
                               | Error document is a script that |  |
                               | generates a form where the user |  |
                 return        | enters authentication           |  |
          ^------------------->| credentials (login & password). |  |
         / \      False        +---------------------------------+  |
        /   \                                   |                   |
       /     \                                  |                   |
      /       \                                 V                   |
     /         \               +---------------------------------+  |
    /   Pass    \              | User's client submits this form |  |
   /   user's    \             | to the LOGIN URL, which calls   |  |
   | credentials |<------------| AuthCookie->login().            |  |
   \     to      /             +---------------------------------+  |
    \authen_cred/                                                   |
     \ function/                                                    |
      \       /                                                     |
       \     /                                                      |
        \   /            +------------------------------------+     |
         \ /   return    | Authen cred returns a session      |  +--+
          V------------->| key which is opaque to AuthCookie.*|  |
                True     +------------------------------------+  |
                                              |                  |
               +--------------------+         |      +---------------+
               |                    |         |      | If we had a   |
               V                    |         V      | cookie, add   |
  +----------------------------+  r |         ^      | a Set-Cookie  |
  | If we didn't have a session|  e |T       / \     | header to     |
  | key cookie, add a          |  t |r      /   \    | override the  |
  | Set-Cookie header with this|  u |u     /     \   | invalid cookie|
  | session key. Client then   |  r |e    /       \  +---------------+
  | returns session key with   |  n |    /  pass   \               ^    
  | successive requests        |    |   /  session  \              |
  +----------------------------+    |  /   key to    \    return   |
               |                    +-| authen_ses_key|------------+
               V                       \             /     False
  +-----------------------------------+ \           /
  | Tell Apache to set Expires header,|  \         /
  | set user to user ID returned by   |   \       /
  | authen_ses_key, set authentication|    \     /
  | to our type (e.g. AuthCookie).    |     \   /
  +-----------------------------------+      \ /
                                              V
         (---------------------)              ^
         ( Request a protected )              |
         ( page, user has a    )--------------+
         ( session key cookie  )
         (---------------------)


 *  The session key that the client gets can be anything you want.  For
    example, encrypted information about the user, a hash of the
    username and password (similar in function to Digest
    authentication), or the user name and password in plain text
    (similar in function to HTTP Basic authentication).

    The only requirement is that the authen_ses_key function that you
    create must be able to determine if this session_key is valid and
    map it back to the originally authenticated user ID.

=for html
</PRE>

=head1 METHODS

C<Apache::AuthCookie> has several methods you should know about.  Here
is the documentation for each. =)

=over 4

=item * authenticate()

This method is one you'll use in a server config file (httpd.conf,
.htaccess, ...) as a PerlAuthenHandler.  If the user provided a
session key in a cookie, the C<authen_ses_key()> method will get
called to check whether the key is valid.  If not, or if there is no
key provided, we redirect to the login form.

=item * authorize()

This will step through the C<require> directives you've given for
protected documents and make sure the user passes muster.  The
C<require valid-user> and C<require user joey-jojo> directives are
handled for you.  You can implement custom directives, such as
C<require species hamster>, by defining a method called C<species()>
in your subclass, which will then be called.  The method will be
called as C<$r-E<gt>species($r, $args)>, where C<$args> is everything
on your C<require> line after the word C<species>.  The method should
return OK on success and HTTP_FORBIDDEN on failure.

=item * authen_cred()

You must define this method yourself in your subclass of
C<Apache::AuthCookie>.  Its job is to create the session key that will
be preserved in the user's cookie.  The arguments passed to it are:

 sub authen_cred ($$\@) {
   my $self = shift;  # Package name (same as AuthName directive)
   my $r    = shift;  # Apache request object
   my @cred = @_;     # Credentials from login form

   ...blah blah blah, create a session key...
   return $session_key;
 }

The only limitation on the session key is that you should be able to
look at it later and determine the user's username.  You are
responsible for implementing your own session key format.  A typical
format is to make a string that contains the username, an expiration
time, whatever else you need, and an MD5 hash of all that data
together with a secret key.  The hash will ensure that the user
doesn't tamper with the session key.  More info in the Eagle book.

=item * authen_ses_key()

You must define this method yourself in your subclass of
Apache::AuthCookie.  Its job is to look at a session key and determine
whether it is valid.  If so, it returns the username of the
authenticated user.

 sub authen_ses_key ($$$) {
   my ($self, $r, $session_key) = @_;
   ...blah blah blah, check whether $session_key is valid...
   return $ok ? $username : undef;
 }

Optionally, return an array of 2 or more items that will be passed to method
custom_errors. It is the responsibility of this method to return the correct
response to the main Apache module.

=item * custom_errors($r,@_)

Note: this interface is experimental.

This method handles the server response when you wish to access the Apache
custom_response method. Any suitable response can be used. this is
particularly useful when implementing 'by directory' access control using
the user authentication information. i.e.

        /restricted
                /one            user is allowed access here
                /two            not here
                /three          AND here

The authen_ses_key method would return a normal response when the user attempts
to access 'one' or 'three' but return (NOT_FOUND, 'File not found') if an
attempt was made to access subdirectory 'two'. Or, in the case of expired
credentials, (AUTH_REQUIRED,'Your session has timed out, you must login
again').

  example 'custom_errors'

  sub custom_errors {
    my ($self,$r,$CODE,$msg) = @_;
    # return custom message else use the server's standard message
    $r->custom_response($CODE, $msg) if $msg;
    return($CODE);
  }
          
  where CODE is a valid code from Apache::Constants

=item * login()

This method handles the submission of the login form.  It will call
the C<authen_cred()> method, passing it C<$r> and all the submitted
data with names like C<"credential_#">, where # is a number.  These will
be passed in a simple array, so the prototype is
C<$self-E<gt>authen_cred($r, @credentials)>.  After calling
C<authen_cred()>, we set the user's cookie and redirect to the
URL contained in the C<"destination"> submitted form field.

=item * login_form($r)

This method is responsible for displaying the login form. The default
implementation will make an internal redirect and display the URL you
specified with the C<PerlSetVar WhatEverLoginScript> configuration
directive. You can overwrite this method to provide your own
mechanism.

=item * logout()

This is simply a convenience method that unsets the session key for
you.  You can call it in your logout scripts.  Usually this looks like
C<$r-E<gt>auth_type-E<gt>logout($r);>.

=item * send_cookie($r, $session_key)

By default this method simply sends out the session key you give it.
If you need to change the default behavior (perhaps to update a
timestamp in the key) you can override this method.

=item * recognize_user()

If the user has provided a valid session key but the document isn't
protected, this method will set C<$r-E<gt>user>
anyway.  Use it as a PerlFixupHandler, unless you have a better idea.

=item * key($r)

This method will return the current session key, if any.  This can be
handy inside a method that implements a C<require> directive check
(like the C<species> method discussed above) if you put any extra
information like clearances or whatever into the session key.

=item * untaint_destination($self, $uri)

This method returns a modified version of the destination parameter
before embedding it into the response header. Per default it escapes
CR, LF and TAB characters of the uri to avoid certain types of
security attacks. You can override it to more limit the allowed
destinations, e.g., only allow relative uris, only special hosts or
only limited set of characters.

=back

=head1 EXAMPLE

For an example of how to use Apache::AuthCookie, you may want to check
out the test suite, which runs AuthCookie through a few of its paces.
The documents are located in t/eg/, and you may want to peruse
t/real.t to see the generated httpd.conf file (at the bottom of
real.t) and check out what requests it's making of the server (at the
top of real.t).

=head1 THE LOGIN SCRIPT

You will need to create a login script (called login.pl above) that
generates an HTML form for the user to fill out.  You might generate
the page using a ModPerl::Registry script, a HTML::Mason component, an Apache
handler, or perhaps even using a static HTML page.  It's usually useful to
generate it dynamically so that you can define the 'destination' field
correctly (see below).

The following fields must be present in the form:

=over 4

=item 1.

The ACTION of the form must be /LOGIN (or whatever you defined in your
server configuration as handled by the ->login() method - see example
in the SYNOPSIS section).

=item 2.

The various user input fields (username, passwords, etc.) must be
named 'credential_0', 'credential_1', etc. on the form.  These will
get passed to your authen_cred() method.

=item 3.

You must define a form field called 'destination' that tells
AuthCookie where to redirect the request after successfully logging
in.  Typically this value is obtained from C<$r-E<gt>prev-E<gt>uri>.
See the login.pl script in t/eg/.

=back

In addition, you might want your login page to be able to tell why
the user is being asked to log in.  In other words, if the user sent
bad credentials, then it might be useful to display an error message
saying that the given username or password are invalid.  Also, it
might be useful to determine the difference between a user that sent
an invalid auth cookie, and a user that sent no auth cookie at all.  To
cope with these situations, B<AuthCookie> will set
C<$r-E<gt>subprocess_env('AuthCookieReason')> to one of the following values.

=over 4

=item I<no_cookie>

The user presented no cookie at all.  Typically this means the user is
trying to log in for the first time.

=item I<bad_cookie>

The cookie the user presented is invalid.  Typically this means that the user
is not allowed access to the given page.

=item I<bad_credentials>

The user tried to log in, but the credentials that were passed are invalid.

=back

You can examine this value in your login form by examining
C<$r-E<gt>prev-E<gt>subprocess_env('AuthCookieReason')> (because it's
a sub-request).

Of course, if you want to give more specific information about why
access failed when a cookie is present, your C<authen_ses_key()>
method can set arbitrary entries in C<$r-E<gt>subprocess_env>.

=head1 THE LOGOUT SCRIPT

If you want to let users log themselves out (something that can't be
done using Basic Auth), you need to create a logout script.  For an example,
see t/htdocs/docs/logout.pl.  Logout scripts may want to take advantage of
AuthCookie's C<logout()> method, which will set the proper cookie headers in
order to clear the user's cookie.  This usually looks like
C<$r-E<gt>auth_type-E<gt>logout($r);>.

Note that if you don't necessarily trust your users, you can't count
on cookie deletion for logging out.  You'll have to expire some
server-side login information too.  AuthCookie doesn't do this for
you, you have to handle it yourself.

=head1 ABOUT SESSION KEYS

Unlike the sample AuthCookieHandler, you have you verify the user's
login and password in C<authen_cred()>, then you do something
like:

    my $date = localtime;
    my $ses_key = MD5->hexhash(join(';', $date, $PID, $PAC));

save C<$ses_key> along with the user's login, and return C<$ses_key>.

Now C<authen_ses_key()> looks up the C<$ses_key> passed to it and
returns the saved login.  I use Oracle to store the session key and
retrieve it later, see the ToDo section below for some other ideas.

=head1 KNOWN LIMITATIONS

If the first unauthenticated request is a POST, it will be changed to
a GET after the user fills out the login forms, and POSTed data will
be lost.

=head2 TO DO

=over 4

=item *

There ought to be a way to solve the POST problem in the LIMITATIONS
section.  It involves being able to re-insert the POSTed content into
the request stream after the user authenticates.

It might be nice if the logout method could accept some parameters
that could make it easy to redirect the user to another URI, or
whatever.  I'd have to think about the options needed before I
implement anything, though.

=back

=head1 CVS REVISION

$Id: AuthCookie.pm 227 2008-04-16 14:59:56Z mschout $

=head1 AUTHOR

Michael Schout <mschout@gkg.net>

Originally written by Eric Bartley <bartley@purdue.edu>

versions 2.x were written by Ken Williams <ken@forum.swarthmore.edu>

=head1 COPYRIGHT

Copyright (c) 2000 Ken Williams. All rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<perl(1)>, L<mod_perl(1)>, L<Apache(1)>.

=cut

# vim: sw=4 ts=4 ai et
