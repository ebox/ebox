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

package EBox::CGI::Controller::DataTable;

use strict;
use warnings;

use base 'EBox::CGI::ClientRawBase';

use EBox::Gettext;
use EBox::Global;
use EBox::Exceptions::NotImplemented;

# Dependencies
use Error qw(:try);
use Clone;

sub new # (cgi=?)
{
    my $class = shift;
    my %params = @_;
    my $tableModel = delete $params{'tableModel'};
    my $template;
    if (defined($tableModel)) {
        $template = $tableModel->Viewer();
    }
    my $self = $class->SUPER::new('template' => $template,
            @_);
    $self->{'tableModel'} = $tableModel;
    bless($self, $class);
    return  $self;
}

sub getParams
{
    my $self = shift;

    my $tableDesc = $self->{'tableModel'}->table()->{'tableDescription'};

    my %params;
    foreach my $field (@{$tableDesc}) {
        foreach my $fieldName ($field->fields()) {
            my $value;
            if ( $field->allowUnsafeChars() ) {
                $value = $self->unsafeParam($fieldName);
            } else {
                $value = $self->param($fieldName);
            }
            # TODO Review code to see if we are actually checking
            # types which are not optional
                    $params{$fieldName} = $value;
        }
    }

    $params{'id'} = $self->param('id');
    $params{'filter'} = $self->param('filter');

    return %params;
}

sub addRow
{
    my $self = shift;

    my $model = $self->{'tableModel'};
    $model->addRow($self->getParams());
}

sub moveRow
{
    my $self = shift;

    my $model = $self->{'tableModel'};

    $self->_requireParam('id');
    $self->_requireParam('dir');

    my $id = $self->param('id');
    my $dir = $self->param('dir');

    if ($dir eq 'up') {
        $model->moveUp($id);
    } else {
        $model->moveDown($id);
    }
}

sub removeRow()
{
    my $self = shift;

    my $model = $self->{'tableModel'};

    $self->_requireParam('id');
    my $id = $self->param('id');
    my $force = $self->param('force');

    $model->removeRow($id, $force);
}

sub editField
{
    my $self = shift;

    my $model = $self->{'tableModel'};
    my %params = $self->getParams();
    my $force = $self->param('force');
    $model->setRow($force, %params);

    my $editField = $self->param('editfield');
    if (not $editField) {
        return;
    }

    my $tableDesc = $self->{'tableModel'}->table()->{'tableDescription'};
    foreach my $field (@{$tableDesc}) {
        my $fieldName = $field->{'fieldName'};
        if ($editField ne $fieldName) {
            next;
        }
        my $fieldType = $field->{'type'};
        if ($fieldType  eq 'text' or $fieldType eq 'int') {
            $self->{'to_print'} = $params{$fieldName};
        }
    }

}


sub editBoolean
{
    my $self = shift;

    my $model = $self->{'tableModel'};
    my $id = $self->param('id');
    my $field = $self->param('field');
    my $value = 0;
    if ($self->param('value')) {
        $value = 1;
    }

    my $currentRow = $model->row($id);
    my $element = $currentRow->elementByName($field);
    $element->setValue($value);
    $model->setTypedRow( $id, { $field => $element},
                        force => 1,
                        readOnly => 0);
    $model->popMessage();
    my $global = EBox::Global->getInstance();
    if ($global->unsaved()) {
        print '$("changes_menu").className = "changed"';
    }
}


# Method to refresh the table by calling rows method
sub refreshTable
{
    my $self = shift;

    my $model = $self->{'tableModel'};
    my $global = EBox::Global->getInstance();

    my $filter = $self->param('filter');
    my $page = $self->param('page');
    my $pageSize = $self->param('pageSize');
    if ( defined ( $pageSize )) {
        $model->setPageSize($pageSize);
    }
#    my $rows = $model->rows($filter, $page);
#    my $tpages = $model->pages($filter);
    my $rows = undef;
    my $tpages = 1000;
    my @params;
    push(@params, 'data' => $rows);
    push(@params, 'dataTable' => $model->table());
    push(@params, 'model' => $model);
    push(@params, 'action' => $self->{'action'});
    push(@params, 'editid' => $self->param('editid'));
    push(@params, 'hasChanged' => $global->unsaved());
    push(@params, 'filter' => $filter);
    push(@params, 'page' => $page);
    push(@params, 'tpages' => $tpages);

    $self->{'params'} = \@params;

}

# Group: Protected methods

sub _process
{
    my $self = shift;

    $self->_requireParam('action');
    my $action = $self->param('action');
    $self->{'action'} = $action;

    my $model = $self->{'tableModel'};

    my $directory = $self->param('directory');
    if ($directory) {

        $model->setDirectory($directory);
    }

    if ($action eq 'edit') {

        $self->editField();
        $self->refreshTable();

    } elsif ($action eq 'add') {

        $self->addRow();
        $self->refreshTable();

    } elsif ($action eq 'del') {

        $self->removeRow();
        $self->refreshTable();

    } elsif ($action eq 'move') {

        $self->moveRow();
        $self->refreshTable();

    } elsif ($action eq 'changeAdd') {

        $self->refreshTable();

    } elsif ($action eq 'changeList') {

        $self->refreshTable();

    } elsif ($action eq 'changeEdit') {

        $self->refreshTable();

    } elsif ($action eq 'view') {
        # This action will show the whole table (including the
        # table header similarly View Base CGI but inheriting
        # from ClientRawBase instead of ClientBase
        $self->{template} = $model->Viewer();
        $self->refreshTable();
    } elsif ($action eq 'editBoolean') {
        delete $self->{template};
        $self->editBoolean();
    }
}

sub _redirect
{
    my $self = shift;

    my $model = $self->{'tableModel'};

    return unless (defined($model));

    return $model->popRedirection();
}

# TODO: Move this function to the proper place
sub _printRedirect
{
    my $self = shift;
    my $url = $self->_redirect();
    return unless (defined($url));
    print "<script>window.location.href='$url'</script>";
}

sub _print
{
    my $self = shift;

    $self->SUPER::_print();
    $self->_printRedirect;
}

1;
