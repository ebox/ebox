#!/usr/bin/perl -w

# Copyright (C) 2007 Warp Networks S.L.
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

# A SOAP client

use Data::Dumper;
use SOAP::Lite;

# SSL stuff
$ENV{HTTPS_CERT_FILE} = 'certs/control center-cert.pem';
$ENV{HTTPS_KEY_FILE}  = 'certs/control center-private-key.pem';
$ENV{HTTPS_CA_FILE} = '/etc/ebox/ssl.crt/ebox.cert';
#$ENV{HTTPS_CA_FILE} = 'certs/cas/cacert.pem';
#$ENV{HTTPS_CA_DIR} = 'certs/cas/';

# debugging (SSL diagnostics)
#$ENV{HTTPS_DEBUG} = 1;

# default ssl version
$ENV{HTTPS_VERSION} = '3';

my $soapConn = new SOAP::Lite
  uri      => 'http://ebox-platform.com/EBox/SOAP/Global',
  proxy    => 'https://192.168.45.131:44300/soap',
  on_fault => sub {
                   my ($soap, $res) = @_;
		   if ( ref $res ) {
		     die $res->faultstring() . $/;
		   }
		   else {
		     die $soap->transport()->status() . $/;
		   }
		 }
  ;

my $response = $soapConn->call(new => qw());
my $globalRem = $response->result();
print 'Get the remote object ' . $/;

$response = $soapConn->isReadOnly($globalRem);
print 'Is read only instance?: ' . ( $response->result() ? 'true' : 'false' ) . $/;

$response = $soapConn->modNames($globalRem);
print 'EBox module names: ' . (join ', ', @{$response->result()}) . $/;

$response = $soapConn->modExists($globalRem, 'ca');
print 'EBox module ca exists? ' . $response->result() . $/;

$response = $soapConn->modMethod($globalRem, 'ca', 'isCreated');
print 'Is eBox CA created? ' . $response->result() . $/;

$response = $soapConn->modMethod($globalRem, 'ca', '_foo');
print 'Calling private method ' . $response->result() . $/;

$response = $soapConn->modMethod($globalRem, 'ca', 'foobar');
print 'Calling to an undefined method ' . $response->result() . $/;
