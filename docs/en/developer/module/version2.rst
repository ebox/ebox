===========================
Version 0.2: adding a table
===========================

Next iteration. So far our module only manages the listening port. This is way too trivial. In this iteration we will manage apache modules, but in a simple way for sake of clarity. We will let the user enable disable some of the modules shipped along with apache.

In Ubuntu and Debian, there are a couple of apache directories which are of interest for this task: */etc/apache2/mods-available* and */etc/apache2/mods-enabled*. The system administrator can enable a module by symliking a couple of files. There's a tool called *a2enmod* that makes this task automatic.

Let's pick a few modules to be managed by eBox:

* ssl
* info
* status
* version

In our first version, our UI will look like a table that the user can add rows to. Every row will represent one of the above modules, and will have a field to indicate if the module is enabled or disabled. We will only take care of the modules listed in this table, i.e., if the module has not been added as a row in the table we will not touch its configuration and we will leave it as it is.

==== Data model ====

The data model to manage modules is pretty simple, we will need a field to store the module name and another field to enable and disable the module.

We will use *ebox-moddev-model*, a tool that allows us to easily add new models to our eBox module. Within the apache2 directory run::

    ebox-moddev-model  --main-class Apache2 --name Modules --field module:Select --field enabled:Boolean --model table

The above command adds a new model called *Modules* which is composed of a *Select* type called *module* and a *Boolean* type called *enabled*. The type of model is a *table* instead of a *form* as we did in version 0.1. *main-class* is *Apache2* as you should recall from the initial module creation.

Build and install the package.

For now there's no menu entry to check the view associated to this module, but we can easily guess the URL as we know the model name. Fire up to browser, log in eBox and go to *http://your_ip/ebox/Apache/View/Modules*. You will see something like this:

.. image:: images/modules-1.png

If you click on the *Add new* link you will see:

.. image:: images/modules-2.png

Let's modify our new model. First of all, we have to populate the available options for the drop-down box, i.e: our *Select* type, with the apache modules we plan to support.

Open *src/EBox/Model/Modules.pm* and go to the function called *populate_module*. We will modify it to look similar to this::

    #!perl
    #
    #   Callback function to fill out the values that can
    #   be picked from the <EBox::Types::Select> field module
    #
    # Returns:
    #
    #   Array ref of hash refs containing:
    #
    #
    sub populate_module
    {

            return [
                     {
                            value => 'ssl',
                            printableValue => 'SSL',
                     },
                     {
                            value => 'info',
                            printableValue => 'Info',
                     },
                     {
                            value => 'status',
                            printableValue => 'Status',
                     },
                     {
                            value => 'version',
                            printableValue => 'Version',
                     },
            ];

    }

*populate_module* is a callback that will be called by our field *module* which is a *Select* type to populate the available options within the drop-down box. Check out the code which instances this type and how we pass a pointer to this method using the attribute *populate*::

    #!perl
    ...
        my @tableHead =
        (
            new EBox::Types::Select(
                'fieldName' => 'module',
                'printableName' => __('module'),
                'populate' => \&populate_module,
                'unique' => 1,
                'editable' => 1
            ),
    ...

We are going to change a few things within the *_table* function in our model. After the changes it should look like this::

    #!perl
    sub _table
    {
        my @tableHead =
        (
            new EBox::Types::Select(
                'fieldName' => 'module',
                'printableName' => __('Module'),
                'populate' => \&populate_module,
                'unique' => 1,
                'editable' => 1
            ),
            new EBox::Types::Boolean(
                'fieldName' => 'enabled',
                'printableName' => __('Enabled'),
                'editable' => 1
            ),
        );
        my $dataTable =
        {
            'tableName' => 'Modules',
            'printableTableName' => __('Modules'),
            'modelDomain' => 'Apache2',
            'defaultActions' => ['add', 'del', 'editField', 'changeView' ],
            'tableDescription' => \@tableHead,
            'printableRowName'=> __('Apache module'),
            'sortedBy' => 'module',
            'help' => *, # FIXME
        };

        return $dataTable;
    }

We have modified both *printableName* attributes to make the first letter uppercase. We have removed two attributes from the *Enable* field: *unique* and *size*. The former tells the framework not to allow two rows with the same value in that field, and the latter is a hint for the UI view which doesn't make sense in a boolean type either. We have also added two fields to our data table description: *printableRowName* which is the name that will be used to show information to the user when an action takes place on a row, and *sortedBy* which tells the framework to order the table using a given field, in this case *module*.

Build and install the module as usual. Fire up the browser and go to *! http://your_ip/ebox/Apache/View/Modules* to check your changes. Add a couple of rows and your module should look like this:

.. image:: images/modules-3.png

Fetching the stored values
==========================

As we did in version 0.1, let's implement a simple external script to read the values stored in our new model. The script is as simple as this::

    #!perl
    use EBox;
    use EBox::Model::ModelManager;
    use EBox::Global;

    # This is the very first thing we always have to do from external scripts
    EBox::init();

    # Instance ModelManager
    my $manager = EBox::Model::ModelManager->instance();

    # Gently ask for the model called apache2/Modules
    my $modules= $manager->model('apache2/Modules');

    # Iterates over the rows and print info
    for my $id (@{$modules->ids()}) {
            my $row = $modules->row($id);
            my $name = $row->valueByName('module');
            my $enabled = $row->valueByName('enabled');
            print "Module: $name enabled $enabled\n";
    }

We will skip the first part and we will go directly into the loop. As you
can see, we iterate over every row that is stored in our model. We use the
method *ids()* (remember our model inherits from *EBox::Model::DataTable*)
to fetch the row identifiers. And for every identifier we retrieve its row
by calling *row()*. Then we fetch the value for the two fields that make it
up: *module*, and *enabled*. The method *valueByName*, as we have already
seen, takes care of looking up the field and returning its value.

Writing the apache configuration
================================

We will take advantage of *a2enmod* and *a2dismod* script to enable and disable apache modules. These scripts take care of symlinking the relevant files to carry out the actions. Their use is straightforward::

    a2enmod module_name

In our main class (*src/EBox/Apache2.pm*) we will implement a private method called *_configureModules* which will iterate over the configured modules and will run *a2enmod* if the module is enabled, or *a2dismod* if it's disabled. The method will look like this::

    #!perl
    # Method: _configureModules
    #
    #       This method is used to enable or disable apache modules based
    #       on the user configuration.
    #
    sub _configureModules
    {
            my ($self) = @_;

            my $mgr = EBox::Model::ModelManager->instance();
            my $model = $mgr->model('apache2/Modules');

            for my $id (@{$model->ids()}) {
                    my $row = $model->row($id);
                    my $module = $row->valueByName('module');
                    my $enabled = $row->valueByName('enabled');
                    if ($enabled) {
                            EBox::Sudo::root("a2enmod $module");
                    } else {
                            EBox::Sudo::root("a2dismod $module");
                    }
            }
    }

The last thing to do is call this method from the *_setConf* method. Remember that that this is the method which is called by *_regenConfig* when the user saves changes. It should look something like this::

    #!perl
    # Method: _setConf
    #
    #       Overrides <EBox::Module::Service::_setConf>
    #
    sub _setConf
    {
            my ($self) = @_;

            $self->_writeConfiguration();
            $self->_configureModules();
    }
