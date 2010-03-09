package EBox::Migration::Helpers;
use strict;
use warnings;

use EBox;

use String::ShellQuote;


# SQL helpers

sub runQuery
{
    my ($query) = @_;

    my $psql = String::ShellQuote::shell_quote("psql eboxlogs -c \"$query\"");
    my $cmd = qq{sudo su postgres -c $psql > /dev/null 2>&1};
    system $cmd;
    return $?;
}

sub renameTable
{
    my ($oldTable, $newTable) = @_;

    my $exists_query = "SELECT COUNT(*) FROM $oldTable";
    my @queries = (
        "ALTER TABLE $newTable RENAME TO $newTable" . "_new",
        "ALTER TABLE $oldTable RENAME TO $newTable",
        "INSERT INTO $newTable SELECT * FROM $newTable" . "_new",
        "DROP TABLE $newTable" . "_new"
    );

    my $res = runQuery($exists_query);
    if ($res == 0) {
        for my $q (@queries) {
            runQuery($q);
        }
    }
}

sub renameConsolidationTable
{
    my ($oldTable, $newTable) = @_;

    my @types = ('hourly', 'daily', 'weekly', 'monthly');

    for my $t (@types) {
        renameTable($oldTable . "_$t", $newTable . "_$t");
    }
}

sub renameField
{
    my ($table, $oldField, $newField) = @_;

    my $query = "ALTER TABLE $table RENAME COLUMN $oldField TO $newField";
    runQuery($query);
}

sub createIndex
{
    my ($table, $field) = @_;

    my $query = "CREATE INDEX $table" . "_$field" . "_i ON $table($field)";
    runQuery($query);
}

sub createTimestampIndex
{
    my ($table) = @_;
    createIndex($table, 'timestamp');
}

sub dropIndex
{
    my ($index) = @_;

    my $query = "DROP INDEX $index"; 
    runQuery($query);
}


sub addColumn
{
    my ($table, $column, $columnData) = @_;
    my $exists_query = "SELECT COUNT(*) FROM $table";
    my $res = runQuery($exists_query);
    if ($res == 0) {
        $exists_query = "SELECT $column FROM $table LIMIT 1";
        my $exists = runQuery($exists_query) == 0;
        if ($exists) {
            return;
        }
        my $addColumnQuery = "ALTER TABLE $table " .
                             "ADD COLUMN $column " .
                             "$columnData";
        runQuery($addColumnQuery);
    }
}

1;
