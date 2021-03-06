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

# Class:
#
#   EBox::Logs::Model::ConfigureLogDataTable
#
#   This class is used as a model to describe a table which will be
#   used to select the logs domains the user wants to enable/disable.
#
#   It subclasses <EBox::Model::DataTable>
#
#
#

package EBox::Logs::Model::ConfigureLogDataTable;

use strict;
use warnings;

# eBox classes
use EBox::Global;
use EBox::Gettext;
use EBox::Model::ModelManager;
use EBox::Validate qw(:all);
use EBox::Types::Boolean;
use EBox::Types::Int;
use EBox::Types::IPAddr;
use EBox::Types::Link;
use EBox::Types::Select;
use EBox::Types::Text;
use EBox::Types::Union;
use EBox::Sudo;
# eBox exceptions used
use EBox::Exceptions::External;

# Core modules
use Error qw(:try);
use List::Util;

use base 'EBox::Model::DataTable';

# Group: Public methods

sub new
{
    my $class = shift;
    my %parms = @_;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}


# Method: enabledLogs
#
#   Return those log domains which must be logged.
#
# Returns:
#
#   Hashref containing the enabled logs.
#
#   Example:
#
#       { 'squid' =>  1, 'dhcp' => 1 }
#
#
sub enabledLogs
{
    my ($self) = @_;

    my %enabledLogs;
    for my $id (@{$self->ids()}) {
        my $row = $self->row($id);
        next unless ($row->valueByName('enabled'));
        $enabledLogs{$row->valueByName('domain')}  = 1;
    }
    return \%enabledLogs;
}

# Method: syncRows
#
#       Override <EBox::Model::DataTable::syncRows>
#
#   It is overriden because this table is kind of different in
#   comparation to the normal use of generic data tables.
#
#   - The user does not add rows. When we detect the table is
#   empty we populate the table with the available log domains.
#
#   - We check if we have to add/remove one the log domains. That happens
#   when a new module is installed or an existing one is removed.
#
#
sub syncRows
{
    my ($self, $currentRows) = @_;

    my $logs = EBox::Global->modInstance('logs');
    my $changed = undef;

    # Fetch the current log domains stored in gconf
    my %storedLogDomains;
    foreach my $id (@{$currentRows}) {
        my $row = $self->row($id);
        $storedLogDomains{$row->valueByName('domain')} = 1;
    }

    # Fetch the current available log domains
    my %currentLogDomains;
    foreach my $mod (@{ $logs->getLogsModules()}  ) {
      $currentLogDomains{$mod->name} = $mod;
    }

    # Add new domains to gconf
    foreach my $domain (keys %currentLogDomains) {
        next if (exists $storedLogDomains{$domain});

        my @tableInfos;
        my $mod = $currentLogDomains{$domain};
        my $ti = $mod->tableInfo();

        if (ref $ti eq 'HASH') {
            EBox::warn('tableInfo() in ' . $mod->name .
             'must return a reference to a list of hashes not the hash itself');
            @tableInfos = ( $ti );
        }
        else {
            @tableInfos = @{ $ti };
        }

        my $enabled = not grep {
          $_->{'disabledByDefault'}
        } @tableInfos;



        $self->addRow(domain => $domain,
                      enabled => $enabled,
                      lifeTime => 168);
        $changed = 1;
    }

    # Remove non-existing domains from gconf
    foreach my $id (@{$currentRows}) {
        my $row = $self->row($id);
        my $domain = $row->valueByName('domain');
        next if (exists $currentLogDomains{$domain});
        $self->removeRow($row->id());
        $changed = 1;
    }

    return $changed;

}

# Method: validateTypedRow
#
#   Override <EBox::Model::DataTable::validateTypedRow>
#
sub updatedRowNotify
{
  my ($self, $row) = @_;

  my $domain = $row->valueByName('domain');
  my $enabled = $row->valueByName('enabled');

  my $logs = EBox::Global->modInstance('logs');
  my $tables = $logs->getAllTables();
  my $index = List::Util::first { $tables->{$_}->{helper}->name() eq $domain }
      keys %{ $tables };

  if ($index) {
      $tables->{$index}->{helper}->enableLog($enabled);
  } else {
      EBox::warn("Domain: $domain does not exist in logs");
  }
}

# Group: Callback functions

# Function: filterDomain
#
#   This is a callback used to filter the output of the field domain.
#   It basically translates the log domain
#
# Parameters:
#
#   instancedType-  an object derivated of <EBox::Types::Abastract>
#
# Return:
#
#   string - translation
sub filterDomain
{
    my ($instancedType) = @_;

    my $logs = EBox::Global->modInstance('logs');

    my $table = $logs->getTableInfo($instancedType->value());

    my $translation = $table->{'name'};

    if ($translation) {
        return $translation;
    } else {
        return $instancedType->value();
    }
}

sub _populateSelectLifeTime
{
    # life time values must be in hours
    return  [
                {
                    printableValue => __('never purge'),
                    value          =>  0,
                },
                {
                    printableValue => __('one hour'),
                    value          => 1,
                },
                {
                    printableValue => __('twelve hours'),
                    value          => 12,
                },
                {
                    printableValue => __('one day'),
                    value          => 24,
                },
                {
                    printableValue => __('three days'),
                    value          => 72,
                },
                {
                    printableValue => __('one week'),
                    value          =>  168,
                },
                {
                    printableValue => __('fifteeen days'),
                    value          =>  360,
                },
                {
                    printableValue => __('thirty days'),
                    value          =>  720,
                },
                {
                    printableValue => __('ninety days'),
                    value          =>  2160,
                },
           ];
}

# Function: acquireEventConfURL
#
#      Callback function used to gather the foreign model view URL to
#      configure the event watcher configuration for this log domain
#
# Parameters:
#
#      instancedType - <EBox::Types::Abstract> the cell from which the
#      URL will be obtained
#
# Returns:
#
#      String - the desired URL
#
sub acquireEventConfURL
{
    my ($instancedType) = @_;

    my $logDomain = $instancedType->row()->valueByName('domain');

    my $modelManager = EBox::Model::ModelManager->instance();

    my $logConfModel  = $modelManager->model('/events/LogWatcherConfiguration');
    my $id  = $logConfModel->findValue(domain => $logDomain);
    my $loggerConfRow = $logConfModel->row($id);
    my $filterDirectory = $loggerConfRow->{filters}->{directory};

    my $logFilteringWatcher;
    try {
        $logFilteringWatcher = $modelManager->model("/events/LogWatcherFiltering/$logDomain");
    } catch EBox::Exceptions::DataNotFound with {
        $logFilteringWatcher = undef;
    };

    if ( $logFilteringWatcher ) {
        return '/ebox/' . $logFilteringWatcher->menuNamespace()
          . "?directory=$filterDirectory";
    } else {
        return '/ebox/';
    }

}

# Group: Protected methods

# Method:  _table
#
# This method overrides <EBox::Model::DataTable::_table> to return
# a table model description.
#
# This table is composed of four fields:
#
#   domain (<EBox::Types::Text>)
#   enabled (<EBox::Types::Boolean>)
#   lifeTime (<EBox::Types::Select>)
#   eventConf (<EBox::Types::Link>)
#
# The only avaiable action is edit and only makes sense for 'enabled'
# and lifeTime.
#
sub _table
{
    my @tableHead =
        (
         new EBox::Types::Text(
                    'fieldName' => 'domain',
                    'printableName' => __('Domain'),
                    'size' => '12',
                    'unique' => 1,
                    'editable' => 0,
                    'filter' => \&filterDomain
                              ),
         new EBox::Types::Boolean(
                    'fieldName' => 'enabled',
                    'printableName' => __('Enabled'),
                    'unique' => 0,
                    'trailingText' => '',
                    'editable' => 1,
                                 ),
         new EBox::Types::Select(
                 'fieldName'     => 'lifeTime',
                 'printableName' => __('Purge logs older than'),
                 'populate'      => \&_populateSelectLifeTime,
                 'editable'      => 1,
                 'defaultValue'  => 168, # one week
                                ),
#         new EBox::Types::Link(
#                  'fieldName'     => 'eventConf',
#                  'printableName' => __('Event configuration'),
#                  'editable'      => 0,
#                  'volatile'      => 1,
#                  'acquirer'      => \&acquireEventConfURL,
#                              ),
        );

    my $dataTable =
        {
            'tableName' => 'ConfigureLogTable',
            'printableTableName' => __('Current configuration'),
            'pageTitle' => __('Logs configuration'),
            'defaultController' => '/ebox/Logs/Controller/ConfigureLogTable',
            'defaultActions' => [ 'editField', 'changeView' ],
            'tableDescription' => \@tableHead,
            'class' => 'dataTable',
            'order' => 0,
            'help' => __x('Enable/disable logging per-module basis'),
            'rowUnique' => 0,
            'printableRowName' => __('logs'),
        };

    return $dataTable;
}

1;

