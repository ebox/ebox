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

# Class: EBox::Model::CompositeProvider
#
#   Interface meant to be used for classes providing composites. That
#   is, those eBox modules which also have composites

package EBox::Model::CompositeProvider;

use base 'EBox::Model::ProviderBase';

use strict;
use warnings;

use constant TYPE => 'composite';

# eBox uses

# Method: composite
#
#
# Parameters:
#          name - composite's name
#
# Returns:
#   a instance of the composite requested
sub composite
{
  my ($self, $name) = @_;
  return  $self->providedInstance(TYPE, $name);
}


# Method: composites
#
#   This method must be overriden in case your module requires no
#   standard-behaviour when creating composites instances. If you override it,
#   the method modelClasses is not longer necessary.
#
#   In most cases you will not need to override it
#
# Returns:
#
#	array ref - containing instances of the composites
#
sub composites
{
  my ($self, $name) = @_;
  return  $self->providedInstances(TYPE, $name);
}

# Method: reloadCompositesOnChange
#
#    This method indicates the composite manager to call again
#    <EBox::Model::ModelProvider::composites> method when an action is
#    performed on a model.
#
# Returns:
#
#    array ref - containing the model name (or context name) when the
#    composite provider want to be notified
#
sub reloadCompositesOnChange
{

    return [];

}

# internal utility function, invokes the composite constructor
sub newCompositeInstance
{
  my ($self,  $class, @params) = @_;
  my $instance = $class->new(@params);

  return $instance;
}

sub addCompositeInstance
{
  my ($self, $path, $instance) = @_;
  $self->addInstance(TYPE, $path, $instance);
}


sub removeCompositeInstance
{
  my ($self, $path, $instance) = @_;
  $self->removeInstance(TYPE, $path, $instance);
}

sub removeAllCompositeInstances
{
  my ($self, $path) = @_;
  $self->removeAllInstances(TYPE, $path);
}

# Method: compositeClasses
#
#  This method must be overriden by all subclasses. It is used to rgister which
#  composites are use by the module.
#
#  It must return a list reference with the following items:
#  -  the names of all composite classes which does not require additional parameters
#  -  hash reference for other composites with the following fields:
#         class      - the name of the class
#         parameters - reference to the list of parameters which we want to 
#                      pass to the composite's constructor
sub compositeClasses
{
  throw EBox::Exceptions::NotImplemented('compositeClasses');
}

1;
