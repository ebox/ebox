# Description:
use strict;
use warnings;

use Test::Builder::Tester tests => 5;
use Test::More ;


use  lib '../..';

use EBox::Global::Mock;
use EBox::Mock;
use Test::MockObject;


BEGIN {  use_ok ('EBox::Test', ':all')  } ;
setUp();
checkModuleInstantiationTest();

sub setUp
{
    EBox::Global::Mock::mock();
    EBox::Mock::mock();
}


sub fakeModules
{
  Test::MockObject->fake_module('EBox::Simple',  
				_create => sub {     
				  my ($class, @params) = @_;
				  my $self =  EBox::GConfModule->_create(name => 'simple', @params);
				  bless $self, $class;
				  return $self;
				}
			       );

  Test::MockObject->fake_module('EBox::Unknown',
				_create => sub {     
				  my ($class, @params) = @_;
				  my $self =  $class->SUPER::_create(@params);
				  bless $self, $class;
				  return $self;
				}
			       );

  Test::MockObject->fake_module('EBox::BadCreate',  
				_create =>    sub {
				  my ($class, @params) = @_;
				  my $self = EBox::GConfModule->_create(name => 'badCreate', @params);
				  bless $self, 'EBox::Macaco';
				  return $self;
				}
			       );


       EBox::Global::Mock::setAllEBoxModules (badCreate => 'EBox::BadCreate', simple => 'EBox::Simple') ;
    # setUp ended

}

sub checkModuleInstantiationTest
{
  # cases setUp:
  fakeModules();



  # straight case
  test_out("ok 1 - simple instantiated correctly");
  checkModuleInstantiation('simple', 'EBox::Simple');
  test_test('checkModuleInstantiation for a simple module');


  # inexistent module
  test_out("not ok 1 - EBox::Inexistent failed to load");
  test_fail(+1);
  checkModuleInstantiation('inexistent', 'EBox::Inexistent');
  test_test('checkModuleInstantiation for a inexistent module');
    
  # module that loads but  EBox::Global is not aware of it
  test_out("not ok 1 - Can not create a instance of the EBox's module unknown");
  test_fail(+1);
  checkModuleInstantiation('unknown', 'EBox::Unknown');
  test_test('checkModuleInstantiation for a unknown module');

  # module that loads but  EBox::Global is not aware of it
  test_out("not ok 1 - The instance returned of badCreate is not of type EBox::BadCreate instead is a EBox::Macaco");
  test_fail(+1);
  checkModuleInstantiation('badCreate', 'EBox::BadCreate');
  test_test('checkModuleInstantiation for a unknown module');
}




1;
