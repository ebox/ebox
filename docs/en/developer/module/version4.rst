=========================
Version 0.4: preload data
=========================

In our current module version, when our users want to enable or disable a module
there are two options. If the module row does not yet exist, they have to add
the row with the desired configuration. Where the module row already exists,
users have to click on the *edit* -pencil icon- button.

From a UI design perspective, it would be nice to have all the module rows added from the very begining. This way, our users will consistently interact with the table in just one way: clicking on the *edit* button.

In this new version we will learn how to *pre-add* rows to a given table. We
will see two different approaches. The first one is not the optimal approach
with the given scenario. However, we will introduce it because it can be useful
with other modules managing different sorts of data.

Approach *a*: overriding *syncRows()*
=====================================
*syncRows()* is a method that can be implemented if you wish to add or delete
some rows before the actual row identifiers array is returned.

The code in *src/EBox/Model/Modules.pm* will be something like this::

    #!perl
    # Method: syncRows
    #
    #   Overrides <EBox::Model::DataTable::syncRows>
    #   to pre-add module rows.
    sub syncRows
    {
        my ($self, $currentRows)  = @_;

        my @modules = ('ssl', 'info', 'status', 'version');
        my %currentModules = map { $self->row($_)->valueByName('module') => 1 }
                         @{$currentRows};

        # Check if there is any module that has not been added yet
        my @modsToAdd = grep { not exists $currentModules{$_} } @modules;

        return 0 unless (@modsToAdd);

        for my $mod (@modsToAdd) {
            $self->add( module => $mod, enabled => 1 );
        }

        return 1;
    }

Let's walk through the above code. *@modules* contains the apache modules that
users will be able to enable from this module. *$currentRows* contains the row
identifiers of the stored rows. Note that we use the module name as the row
identifier. 

In case we do not have to add any row, we just return *0* to tell the framework
that we have not added or removed any row.

Once we have the row, we just add it using *EBox::Model::DataTable::add()*, we
pass it a hash containing every field and its value.

Finally, we return *1* to indicate that we have added new rows.

Approach *b*: migration
=======================

The migration scripts are helpful to add or migrate data. They are usually
used when a new version of an eBox module is released and its data model has
changed. They are also useful to populate values in our models.

A migration script is run only once if there is no error during its execution.

Let's use a new *ebox-moddev* command to add our first migration script.
Within your module directory run::

    ebox-moddev-migration  --main-class apache2 --version 1

This will create our first migration script in *migration/1.pl* that will look
like this::

    #!perl
    #  Migration between gconf data version X and Y
    #
    #       This migration script takes care of... TODO
    #
    use strict;
    use warnings;

    package EBox::Migration;
    use base 'EBox::MigrationBase';

    use strict;
    use warnings;

    use EBox;
    use EBox::Global;
    use EBox::Config;
    use EBox::Sudo;

    # Method: runGConf
    #
    #   Overrides <EBox::MigrationBase::runGConf>
    #
    sub runGConf
    {
        my ($self) = @_;

    }

    # Main

    EBox::init();

    my $module = EBox::Global->modInstance('apache2');
    my $migration = new EBox::Migration(
            'gconfmodule' => $module,
            'version' => 1,
            );
    $migration->execute();

    1;

First of all, we need 
using one of its functions::

    #!perl
    use EBox::Apache2::Model::Modules;

Now we will implement the method *runGConf* which will carry out the data
population. The whole file should look like this::

    #!perl
    #
    #  Migration between gconf data version X and Y
    #
    #       This migration script takes care of... TODO
    #
    use strict;
    use warnings;

    package EBox::Migration;
    use base 'EBox::MigrationBase';

    use strict;
    use warnings;

    use EBox;
    use EBox::Global;
    use EBox::Config;
    use EBox::Sudo;
    use EBox::Apache2::Model::Modules;

    # Method: runGConf
    #
    #   Overrides <EBox::MigrationBase::runGConf>
    #
    sub runGConf
    {
        my ($self) = @_;

        # Fetch the 'apache2/Modules' model to populate
        # $self->{gconfmodule} contains an instance of 'apache2'
        my $model = $self->{gconfmodule}->model('apache2/Modules');

        # We write down those modules that have been already added, if any
        my %existingModels;
        for my $id (@{$model->ids()}) {
            my $row = $model->row($id);
            $existingModels{$row->valueByName('module')} = 1;
        }

        my @modules = ('ssl', 'info', 'status', 'version');
        for my $name (@modules) {
            # If the module has not been added we add it
            next if (exists $existingModels{$name});
            $model->add( module => $module, enabled => $enabled );
        }
    }
    # Main

    EBox::init();

    my $module = EBox::Global->modInstance('apache2');
    my $migration = new EBox::Migration(
            'gconfmodule' => $module,
            'version' => 1,
            );
    $migration->execute();

    1;

