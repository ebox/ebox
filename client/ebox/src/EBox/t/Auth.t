use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Exception;
use Apache::FakeRequest;

use EBox::Mock;
use EBox::Global::Mock;
use EBox::Config::Mock;


use_ok('EBox::Auth');
globalSetUp();
setAndCheckPasswdTest();
authen_cred_test();
authen_ses_key_test();

sub globalSetUp
{
  my $testDir = '/tmp/ebox.auth.test';
  system "rm -rf $testDir";
  ($? == 0) or die "Error deleting $testDir: $!";
  mkdir $testDir or die "Error creating $testDir";

  my $passwd = "$testDir/passwd";
  my $sessionid = "$testDir/sessionid";
  EBox::Config::Mock::mock(passwd => $passwd, sessionid => $sessionid );

  EBox::Mock::mock();
  EBox::Global::Mock::mock();

}


sub setAndCheckPasswdTest
{
  my $auth        = new EBox::Auth;  

  # passwd too short
  dies_ok { $auth->setPassword('12345')  } "Checking for error with a short password";

  my @passwds     = qw(pipadao macaco34 mandril34 ed463fg);
  foreach my $pass (@passwds) {
    lives_ok {  $auth->setPassword($pass) } 'Trying to set new password';
    ok $auth->checkPassword($pass, $pass), 'Checking new password';
  }

}

sub authen_cred_test
{
  my $auth        = new EBox::Auth;
  my $request = _request();

  my $passwd = 'macaco';
  $auth->setPassword($passwd);

  my $badPasswd = $passwd . 'iAmBad';
  ok !$auth->authen_cred($request, $badPasswd), 'authen_cred with bad password';
  
  ok $auth->authen_cred($request, $passwd), 'authen_cred with the correct password';

}


sub authen_ses_key_test
{
  my $auth        = new EBox::Auth;
  my $user        = 'admin';

  my $request = new Apache::FakeRequest(get_remote_host => '10.0.0.2', 'subprocess_env' => undef);
  my $passwd = 'macaco';
  $auth->setPassword($passwd);
  my $sessionKey = $auth->authen_cred($request, $passwd);

  $request = _request();
  is $auth->authen_ses_key($request, $sessionKey), $user, 'Checking user returned by authen_cred';
  ok !$request->subprocess_env, 'Checking apache request subprocess_env field is clear ';

  # try a simultaneous login
  $request = _request();
  my $simultaneousSessionKey = $auth->authen_cred($request, $passwd);
  ok !$auth->authen_ses_key($request, $simultaneousSessionKey), 'Trying a simultaneous login';
  is $request->subprocess_env, 'Already', 'See if apache request subprocess_env field marks the login error';

  $request = _request();
  is $auth->authen_ses_key($request, $sessionKey), $user, 'Checking that simultaneous login has not logged of the first user';
  ok !$request->subprocess_env, 'Checking apache request subprocess_env field is clear ';
  
}


sub _request
{
  my ($host) = @_;
  defined $host or $host = '10.0.0.2';
  return new Apache::FakeRequest(get_remote_host => $host, 'subprocess_env' => undef);
}

1;
