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

# Class: EBox::CGI::Controller::Downloader::FromModel
#
#   This class is a subclass of <EBox::CGI::Controller::Downloader::Base>
#   to download files from a model.
#
#   It will need the following parameters via CGI:
#
#   model  - model name
#   dir - directory to set the model to
#   id - row's id
#   field - the name of a <EBox::Types::File> type
#
package EBox::CGI::Controller::Downloader::FromModel;

use strict;
use warnings;

use base 'EBox::CGI::Controller::Downloader::Base';

use EBox::Gettext;
use EBox::Global;
use EBox::Config;
use EBox::Exceptions::Internal;
use EBox::Model::ModelManager;


# Core modules
use Error qw(:try);

# Group: Public methods

# Constructor: new
#
#      Create a <EBox::CGI::Controller::Downloader:FromTempDir>
#
# Exceptions:
#

#
sub new # (cgi=?)
{

    my ($class, %params) = @_;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    return  $self;
}

# Group: Protected methods

# Method: _path
#
#   This method must be overriden by subclasses to return the path
#   of the file to download
#
# Exceptions:
#
#      <EBox::Exceptions::NotImplemented> - thrown if this method
#      is not implemented by the subclass
sub _path
{
    my ($self) = @_;

    return $self->{path};
}

# Method: _process
#
# Overrides:
#
#      <EBox::CGI::Controller::Downloader::Base::_process>
#
# Exceptions:

#   <EBox::Exceptions::Internal> - If file can't be read or is an invalid path
#   <EBox::Exceptions::Internal> - thrown if the field name is not
#      contained in the given model
#
sub _process
{
    my ($self) = @_;

    $self->_requireParam('model');
    $self->_requireParam('dir');
    $self->_requireParam('id');
    $self->_requireParam('field');

    my $modelName = $self->param('model');
    my $dir = $self->param('dir');
    my $id = $self->param('id');
    my $field = $self->param('field');

    my $model = EBox::Model::ModelManager->instance()->model($modelName);
    $model->setDirectory($dir);
    $model->row($id);
    my $type = $model->row($id)->elementByName($field);
    unless (defined($type) and $type->isa('EBox::Types::File')) {
        throw EBox::Exceptions::Internal("field $field is not a File type");
    }

    unless ($type->exist()) {
        throw EBox::Exceptions::Internal(
                "field $field does not contain a file");
    }

    $self->{path} = $type->path();

    $self->SUPER::_process(@_);
}
1;

