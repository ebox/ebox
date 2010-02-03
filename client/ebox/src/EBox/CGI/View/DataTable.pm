# Copyright (C) 2005 Warp Networks S.L., DBS Servicios Informaticos S.L.
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

package EBox::CGI::View::DataTable;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;

# Group: Public methods

sub new # (cgi=?)
{
	my $class = shift;
	my %params = @_;
	my $tableModel = delete $params{'tableModel'};
	my $self = $class->SUPER::new('template' => $tableModel->Viewer(),
                                      @_);
	$self->{'tableModel'} = $tableModel;
	bless($self, $class);
	return $self;
}

# Group: Protected methods

sub _process
{
	my $self = shift;

	my $global = EBox::Global->getInstance();

        my $model = $self->{'tableModel'};
        $model->setDomain();
        $self->setMenuFolder($model->menuFolder());
        my $directory = $self->param('directory');
        if ($directory) {
            $model->setDirectory($directory);
        }

        if ( $self->param('action') eq 'presetUpdate' ) {
            $self->_presetUpdate();
        } else {
#            my $rows = $model->rows(undef, 0);

 #           my $tpages = $model->pages(undef);
            my @params;
            push(@params, 'data' => undef );
            push(@params, 'dataTable' => $model->table());
            push(@params, 'model'      => $model);
            push(@params, 'hasChanged' => $global->unsaved());
            push(@params, 'tpages' => 0);
            push(@params, 'page' => 0);

            $self->{'params'} = \@params;
        }
}

# Group: Private methods

# Method to check if the given parameters are exactly in the model or
# not and then add
sub _presetUpdate
{
        my ($self) = @_;

        my $model = $self->{'tableModel'};
        my $presetParams = $self->_fillTypes();

        my ($editid, $action) = ( '', $self->param('action'));
        if ( $model->rowUnique() ) {
            # Then, search for the element in order to edit instead of
            # adding a new one
            my $foundId = $self->_findEqualRow($model, $presetParams);
            if ( $foundId ) {
                $editid = $foundId;
            }
        }
        # Not unique or just adding a new unique row
        my $gl = EBox::Global->getInstance();
        my @params;
        push(@params, 'model'        => $model);
        push(@params, 'action'       => $action);
        push(@params, 'hasChanged'   => $gl->unsaved());
        push(@params, 'presetParams' => $presetParams);
        push(@params, 'editid'       => $editid);
        push(@params, 'page'         => 0);

        $self->{'params'} = \@params;

}

# Method to fill a hash with instanced types from the array of CGI
# params
sub _fillTypes
{
	my $self = shift;

	my $tableDesc = $self->{'tableModel'}->table()->{'tableDescription'};

	my %params;
        my $cgiParams = $self->paramsAsHash();
	foreach my $field (@{$tableDesc}) {
            my $instancedType = $field->clone();
            $instancedType->setValue($cgiParams->{$instancedType->fieldName()});
            $params{$field->fieldName()} = $instancedType;
	}

	return \%params;
}

# Method to search for the same row
sub _findEqualRow
{

    my ($self, $model, $presetParams) = @_;

    my $foundId = 0;
    foreach my $id (@{$model->ids()}) {
        my $row = $model->row($id);
        my $valueHash = $row->{'valueHash'};
        my $nEqual = grep { $valueHash->{$_}->isEqualTo($presetParams->{$_}) }
          @{$model->fields()};
        EBox::debug($nEqual);
        next unless ( $nEqual == scalar (@{$model->fields()}));
        $foundId = $row->{'id'};
        last;
    }
    return $foundId;

}

1;
