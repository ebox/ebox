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

package EBox::PgDBEngine;

use strict;
use warnings;

use base qw(EBox::AbstractDBEngine);

use DBI;
use EBox::Gettext;
use EBox::Validate;
use EBox;
use EBox::Exceptions::Internal;

use Params::Validate qw(validate_pos);

use Error qw(:try);

sub new {
        my $class = shift,
        my $self = {};
        bless($self,$class);

        $self->_connect();

        return $self;
}

# Method: _dbname
#
#       This function returns the database name.
#
sub _dbname {
        my $root = EBox::Config::configkey('eboxlogs_dbname');
        ($root) or
        throw EBox::Exceptions::External(__x('You must set the {variable} ' .
                                             'variable in the ebox configuration file',
                                             variable => 'eboxlogs_dbname'));
        return $root;
}

# Method: _dbuser
#
#       This function returns the database user.
#
sub _dbuser {
        my $root = EBox::Config::configkey('eboxlogs_dbuser');
        ($root) or
        throw EBox::Exceptions::External(__x('You must set the {variable} ' .
                                             'variable in the ebox configuration file',
                                            variable => 'eboxlogs_dbuser'));
        return $root;
}

# Method: _dbpass
#
#  This function returns the database user password.
#
sub _dbpass {
        my $root = EBox::Config::configkey('eboxlogs_dbpass');
        ($root) or
        throw EBox::Exceptions::External(__x('You must set the {variable} ' .
                                             'variable in the ebox configuration file',
                                             variable => 'eboxlogs_dbpass'));
        return $root;
}

# Method: _connect
#
#       This function do the necessary operations to establish a connection with the
#       database.
#
sub _connect {
        my $self = shift;

        return if($self->{'dbh'});

        my $dbh = DBI->connect("dbi:Pg:dbname=".$self->_dbname(),
                $self->_dbuser(), $self->_dbpass(), { PrintError => 0});

        unless ($dbh) {
            throw EBox::Exceptions::Internal("Connection DB Error: $DBI::errstr\n");
        }

        $self->{'dbh'} = $dbh;
}

# Method: _disconnect
#
#       This function do the necessary operations to get disconnected from the
#       database.
#
sub _disconnect {
        my $self = shift;

        $self->{'sthinsert'}->finish() if ($self->{'sthinsert'});
        $self->{'dbh'}->disconnect();
        $self->{'dbh'} = undef;
}

sub _prepare {
        my ($self, $sql) = @_;

        $self->{'sthinsert'} =  $self->{'dbh'}->prepare($sql);
        unless ($self->{'sthinsert'}) {
                #throw exception
                EBox::debug("Error preparing sql: $sql\n");
                throw EBox::Exceptions::Internal("Error preparing sql: $sql\n");
        }
}

# Method: insert
#
#       This function do the necessary operations to create and establish an insert
#       operation to a table form the database.
#
# Parameters:
#   $table: The table name to insert data.
#   $values: A hash ref with database fields name and values pairs that do you
#   want to insert to.the table name passed as parameter too.
#
sub insert 
{
    my ($self, $table, $values) = @_;
    my $sql = "INSERT INTO $table ( ";
    
    my @keys = ();
    my @vals = ();
    while(my ($key, $value) = each %$values ) {
        push(@keys, $key);
        push(@vals, $value);
    }
    
    $sql .= join(", ", @keys);
    $sql .= ") VALUES (";
    
    foreach (@vals) {
        $sql .= " ?,";
    }
    $sql = (substr($sql, 0, -1)).')';
    

    $self->_prepare($sql);
    my $err = $self->{'sthinsert'}->execute(@vals);
    if (!$err) {
        #throw exception
        EBox::debug ("Error inserting data: $sql\n" .
                     $self->{dbh}->errstr .
                     " \n"
                    );
        throw EBox::Exceptions::Internal ("Error inserting data: $sql\n" .
                                          $self->{dbh}->errstr .
                                          " \n"
                                         );
    }

}



# Method: query
#
#       This function do the necessary operations to create and establish a query
#       operation to a table form the database.
#
# Parameters:
#   $sql: A string that contains the SQL query.
#   @values: An array with the values to substitute in the query.
#
sub query 
{
    my ($self, $sql, @values) = @_;
        
    my $ret;
    my $err;

        
    $self->_prepare($sql);
    if (@values) {
        $err = $self->{'sthinsert'}->execute(@values);
    } else {
        $err = $self->{'sthinsert'}->execute();
    }
    if (!$err) {
        my $errstr = $self->{'dbh'}->errstr();
        EBox::debug ("Error querying data: $sql , $errstr\n");
        #                 throw EBox::Exceptions::Internal ("Error querying data: $sql , $errstr");
    }
    $ret = $self->{'sthinsert'}->fetchall_arrayref({});
    $self->{'sthinsert'}->finish();
    
    return $ret;
}



# Method: do
#
#   Prepare and execute a single statement. 
#
#
# Parameters:
#   $sql: A string that contains the SQL stament.
#   $attr: 
#   @bind_values
#
#
# Returns : the number of rows affected  
sub do
{
    my ($self, $sql, $attr, @bindValues) = @_;

    my @optionalCallParams;
    if (defined $attr) {
        push @optionalCallParams, $attr;
    }
    if (@bindValues) {
        push @optionalCallParams, @bindValues;
    }


    my $res;

    $res = $self->{dbh}->do($sql, @optionalCallParams);
    if (not defined $res) {
        my $errstr = $self->{'dbh'}->errstr();
        throw EBox::Exceptions::Internal("Error doing statement: $sql , $errstr\n");
    }



    return $res;
}




# Method: dumpDB
#
#         Makes a dump of the database in the specified file
#
# Parameters:
#     $outputFile - output database dump file
#
sub  dumpDB
{
  my ($self, $outputFile) = @_;
  validate_pos(@_, 1, 1);

  my $dbname = _dbname();
  my $dbuser = _dbuser();
  my $eboxHome = EBox::Config::home();

  my $dumpCommand = "HOME=$eboxHome /usr/bin/pg_dump --no-owner --clean --file $outputFile -U $dbuser $dbname";
  my $output = `$dumpCommand`;
  if ($? != 0) {
    EBox::error("The following command raised error: $dumpCommand\nOutput:$output");
    throw EBox::Exceptions::External(__x("Error dumping the postgresql database {name}", name => _dbname()));
  }
}

# Method: restoreDB
#
# restore a database from a dump file.
# WARNING:  This erase all the DB current dara
#
# Parameters:
#      $file - database dump file
#
sub restoreDB
{
  my ($self, $file) = @_;
  validate_pos(@_, 1, 1);

  EBox::info('We wil try to restore the database. This will erase your current data' );
  (-r $file) or throw EBox::Exceptions::External(__x("DB dump file {file} is not readable", file => $file));

  my $dbname = _dbname();
  my $dbuser = _dbuser();
  my $eboxHome = EBox::Config::home();

  my $restoreCommand = "HOME=$eboxHome /usr/bin/psql " 
                       . " --file $file  -U $dbuser $dbname";
  EBox::Sudo::command($restoreCommand);
  EBox::info('Database ' . _dbname() . ' restored' );
}  


sub DESTROY
{
    my ($self) = @_;
    $self->_disconnect();
}

1;
