# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package EBox::Auth;

use strict;
use warnings;

use base qw(Apache::AuthCookie);

use Apache;
use Digest::MD5;
use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Exceptions::Internal;

#By now, the expiration time for session is hardcoded here
use constant EXPIRE => 3600; #In seconds  1h

sub new 
{
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}

# arguments
# 	- session id
# throws
# 	- Internal
# 		- When session file cant be open to write
sub _savesession # (session_id)
{
	my $sid = shift;	
	unless  ( open ( SID, "> " . EBox::Config->sessionid )){
                throw EBox::Exceptions::Internal(
         		      "Could not open to write ". 
	                      EBox::Config->sessionid);
      	}
	print SID $sid . "\t" . time if defined $sid;
	close(SID);
}

# arguments
# 	- password introduced by user
# returns 
# 	- true if pass is correct
# 	- false if not
# throws
# 	- Internal
# 		- When passwd file cant be open to read
sub checkPassword # (password) 
{
        shift;
	my $passwd = shift;
	open(PASSWD, EBox::Config->passwd) or
		throw EBox::Exceptions::Internal('Could not open passwd file');

	my @lines = <PASSWD>;
	close(PASSWD);

	my $filepasswd = $lines[0];
	$filepasswd =~ s/[\n\r]//g;

	my $md5 = Digest::MD5->new;
	$md5->add($passwd);

	my $encpasswd = $md5->hexdigest;
	if ($encpasswd eq $filepasswd) {
		return 1;
	} else {
		return undef;
	}
}

# arguments
# 	- new password introduced by user
# throws
# 	- External
# 		- Passwd is too short
# 	- Interanl
# 		- Passwd file cant be open to write
sub setPassword # (password) 
{
        shift;
	my $passwd = shift;
	unless (length($passwd) > 5) {
		throw EBox::Exceptions::External('The password must be at '.
						 'least 6 characters long');
	}
	open(PASSWD, "> ". EBox::Config->passwd) or
		throw EBox::Exceptions::Internal('Could not open passwd file');

	my $md5 = Digest::MD5->new;
	$md5->add($passwd);
	my $encpasswd = $md5->hexdigest;
	print PASSWD $encpasswd;
	close(PASSWD);
}

# arguments
# 	- Apachre request object
# 	- Credentials
# returns
# 	- Session id if authentication is correct
# 	- false if not
sub authen_cred  # (request, password)
{
        my $self = shift;  # Package name (same as AuthName directive)
        my $r    = shift;  # Apache request object
	my $passwd = shift;

	unless ($self->checkPassword($passwd)) {
		my $log = EBox::Global->logger;
		my $ip  = $r->get_remote_host();
		$log->warn("Failed login from: $ip");
		return;
	}

	my $md5 = Digest::MD5->new;
	$md5->add(rand(10000) + 100000);
	my $sid = $md5->hexdigest;
	_savesession($sid);
	my $global = EBox::Global->getInstance();
	$global->revokeAllModules;
	return $sid;
}

# arguments
# 	- Apache request object
# 	- Session key
# returns 
# 	- true (user) if session is correct
# 	- false if not
# throws
# 	- Internal
# 		- When session id file cant be open to write
# 		- When session id file cant be open to read 
sub authen_ses_key  # (request, session_key) 
{
	my ($self, $r, $session_key) = @_;
	
	unless( -e EBox::Config->sessionid){
		unless  (open (SID,  "> ". EBox::Config->sessionid)){
			 throw EBox::Exceptions::Internal(
	                 "Could not create  ". 
	                 EBox::Config->sessionid);
	         }
		close(SID);
		return;											 
	}
	unless   (open (SID,  EBox::Config->sessionid)){
		 throw EBox::Exceptions::Internal(
			"Could not open ". 
			EBox::Config->sessionid);
	}
	$_ = <SID>;
	my ($sid, $lastime) = split /\t/; 
	my $expires = $lastime + EXPIRE;
	if(($session_key eq $sid) and ( $expires > time )){
		_savesession($sid);
		return "admin";
	}elsif ($expires < time) {
                $r->subprocess_env(LoginReason => "Expired");
		_savesession(undef);
	}else {
		$r->subprocess_env(LoginReason => "Already");
	}

	return;
}

1;
