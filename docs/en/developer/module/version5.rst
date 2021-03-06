==================================
Version 0.5: adding a second table
==================================

In this version we will add support for virtual hosts. As we have done so far,
we will do it in an incremental way, starting from a version with just a few
features.

Data model
==========

We need to create a new model to store the virtual hosts. This initial
version will only have one field called *name* which obviously will store the
name of the virtual host. This field must store fully qualified domain names
(FQDN) and must check that its stored data has a valid syntax. eBox already has
a type that meets our needs: *EBox::Types::DomainName*.

Let's use our beloved *emoddev* tool::

    ebox-moddev-model --main-class Apache2 --name VirtualHosts --model table --field name:DomainName

The above command will create a new model in *src/EBox/Model/VirtualHosts.pm*
whose code will look like this::

    #!perl
    # Copyright
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

    # Class: EBox::Apache2::Model::VirtualHosts
    #
    #   TODO: Document class
    #

    package EBox::Apache2::Model::VirtualHosts;

    use EBox::Gettext;
    use EBox::Validate qw(:all);

    use EBox::Types::DomainName;

    use strict;
    use warnings;

    use base 'EBox::Model::DataTable';

    sub new
    {
            my $class = shift;
            my %parms = @_;

            my $self = $class->SUPER::new(@_);
            bless($self, $class);

            return $self;
    }


    sub _table
    {

        my @tableHead =
        (
            new EBox::Types::DomainName(
                'fieldName' => 'name',
                'printableName' => __('name'),
                'size' => '8',
                'unique' => 1,
                'editable' => 1
            ),
        );
        my $dataTable =
        {
            'tableName' => 'VirtualHosts',
            'printableTableName' => __('VirtualHosts'),
            'modelDomain' => 'Apache2',
            'defaultActions' => ['add', 'del', 'editField', 'changeView' ],
            'tableDescription' => \@tableHead,
            'help' => '', # FIXME
        };

        return $dataTable;
    }

    1;

Now let's make a couple of changes. We will set the printable name of our type
from *name* to *Virtual Host*. We will also tell the framework to order the
table using the *name* field.

Now our model looks like this::

    #!perl
    # Copyright
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

    # Class: EBox::Apache2::Model::VirtualHosts
    #
    #   TODO: Document class
    #

    package EBox::Apache2::Model::VirtualHosts;

    use EBox::Gettext;
    use EBox::Validate qw(:all);

    use EBox::Types::DomainName;

    use strict;
    use warnings;

    use base 'EBox::Model::DataTable';

    sub new
    {
            my $class = shift;
            my %parms = @_;


            my $self = $class->SUPER::new(@_);
            bless($self, $class);

            return $self;
    }


    sub _table
    {

        my @tableHead =
        (
            new EBox::Types::DomainName(
                'fieldName' => 'name',
                'printableName' => __('Virtual Host'), # Changed
                'size' => '8',
                'unique' => 1,
                'editable' => 1
            ),
        );
        my $dataTable =
        {
            'tableName' => 'VirtualHosts',
            'printableTableName' => __('Virtual Hosts'),
            'modelDomain' => 'Apache2',
            'defaultActions' => ['add', 'del', 'editField', 'changeView' ],
            'tableDescription' => \@tableHead,
            'help' => *, # FIXME
            'orderedBy' => 'name', # Changed
        };

        return $dataTable;
    }

    1;

Let's add a new menu entry in the *menu()* entry to *src/EBox/Apache2.pm* as we learnt before::

    #!perl
    # Copyright (C)
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

    # Class: EBox::Apache2
    #
    #   TODO: Documentation

    package EBox::Apache2;

    use strict;
    use warnings;

    use base qw(EBox::GConfModule EBox::Model::ModelProvider
                EBox::ServiceModule::ServiceInterface);


    use EBox::Validate qw( :all );
    use EBox::Global;
    use EBox::Gettext;

    use EBox::Exceptions::InvalidData;
    use EBox::Exceptions::MissingArgument;
    use EBox::Exceptions::DataExists;
    use EBox::Exceptions::DataMissing;
    use EBox::Exceptions::DataNotFound;

    sub _create
    {
        my $class = shift;
        my $self = $class->SUPER::_create(name => 'apache2',
                printableName => __('Apache2'),
                domain => 'ebox-apache2',
                @_);
    }

    ## api functions

    # Overrides:
    #
    #       <EBox::Model::ModelProvider::modelClasses>
    sub modelClasses
    {
        return [
            'EBox::Apache2::Model::Settings',
            'EBox::Apache2::Model::Modules',
            'EBox::Apache2::Model::VirtualHosts',
        ];
    }


    sub domain
    {
        return 'ebox-apache2';
    }

    # Method: actions
    #
    #   Override EBox::ServiceModule::ServiceInterface::actions
    #
    sub actions
    {
        return [];
    }


    # Method: usedFiles
    #
    #   Override EBox::ServiceModule::ServiceInterface::usedFiles
    #
    sub usedFiles
    {
        return [];
    }

    # Method: enableActions
    #
    #   Override EBox::ServiceModule::ServiceInterface::enableActions
    #
    sub enableActions
    {
    }

    # Method: serviceModuleName
    #
    #   Override EBox::ServiceModule::ServiceInterface::serviceModuleName
    #
    sub serviceModuleName
    {
        return 'apache2';
    }

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
                    my $row = $self->row($id);
                    my $module = $row->valueByName('module');
                    my $enabled = $row->valueByName('enabled');
                    if ($enabled) {
                            EBox::Sudo::root("a2enmod $module");
                    } else {
                            EBox::Sudo::root("a2dismod $module");
                    }
            }
    }

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

    # Method: menu
    #
    #       Overrides EBox::Module method.
    #

    #
    sub menu
    {
        my ($self, $root) = @_;

        my $folder = new EBox::Menu::Folder('name' => 'Apache2',
        'text' => __('Apache2'));

        my $settings = new EBox::Menu::Item(
        'url' => 'Apache2/View/Settings',
        'text' => __('Settings'));

        my $modules = new EBox::Menu::Item(
        'url' => 'Apache2/View/Modules',
        'text' => __('Modules'));

        my $virtualHosts = new EBox::Menu::Item(
        'url' => 'Apache2/View/VirtualHosts',
        'text' => __('Virtual Hosts'));


        $folder->add($settings);
        $folder->add($modules);
        $folder->add($virtualHosts);

        $root->add($folder);
    }

    1;

Build and install the package as usual. Click on the Apache2 menu folder entry
and you will see something like this:

.. image:: images/virtual-host-1.png

Now we would like to let the user to enable and disable any virtual host. Your
first thought should be just adding a new boolean field as we did with the *Modules* model. This is not necessary as eBox does it automatically for you under the hood if you set the *enableProperty* value to true. By doing this you are telling the framework to automatically add a new boolean field.

In the method *_table()* in *src/EBox/Model/VirtualHosts.pm* you have to set
*enableProperty* to 1 as follows::

    #!perl
    sub _table
    {

        my @tableHead =
        (
            new EBox::Types::DomainName(
                'fieldName' => 'name',
                'printableName' => __('Virtual Host'),
                'size' => '8',
                'unique' => 1,
                'editable' => 1
            ),
        );
        my $dataTable =
        {
            'tableName' => 'VirtualHosts',
            'printableTableName' => __('Virtual Hosts'),
            'modelDomain' => 'Apache2',
            'defaultActions' => ['add', 'del', 'editField', 'changeView' ],
            'tableDescription' => \@tableHead,
            'help' => *, # FIXME
            'orderedBy' => 'name',
            'enableProperty' => 1, # Change
        };

        return $dataTable;
    }

Build, install and check it out now:

.. image:: images/virtual-host-2.png

Fetching the stored values
==========================

As we did with the previous versions, let's code a simple script so that we can retrieve the stored values::

    #!perl
    use EBox;
    use EBox::Model::ModelManager;
    use EBox::Global;

    # This is the very first thing we always have to do from external scripts
    EBox::init();

    # Instance ModelManager
    my $manager = EBox::Model::ModelManager->instance();

    # Gently ask for the model called apache2/VirtualHosts
    my $modules= $manager->model('apache2/VirtualHosts');

    # Iterates over the rows and print info
    for my $id (@{$modules->ids()}) {
            my $row = $modules->row($id);
            my $name = $row->valueByName('name');
            my $enabled = $row->valueByName('enabled');
            print "Module: $name enabled $enabled\n";
    }

Setting the apache configuration
================================

For every virtual host we will create a file in */etc/apache2/sites-available/*. For those that are available, we will create a link in */etc/apache2/sites-enabled*.

We need to create a *Mason* template to configure every Apache virtual host::

    ebox-moddev-stub --main-class apache2 --name virtual-host.conf

The above command will create a file in *stubs/virtual-host.conf*. You should add the following code::

    <%args>
    $name
    </%args>
    <VirtualHost *:80>
            ServerAdmin webmaster@localhost
            ServerName <% $name %>

            DocumentRoot /var/www/<% $name %>
            <Directory />
                    Options FollowSymLinks
                    AllowOverride None
            </Directory>
            <Directory /var/www/<% $name %>>
                    Options Indexes FollowSymLinks MultiViews
                    AllowOverride None
                    Order allow,deny
                    Allow from all
            </Directory>

            ErrorLog /var/log/apache2/error.log

            # Possible valu
            # alert, emerg.
            LogLevel warn

            CustomLog /var/log/apache2/access.log combined
    </VirtualHost>

As you can see, the only parameter that this template receives is the name of the virtual host. This name is used to configure the *ServerName* and its document root. Check the apache documentation if you want to know what the other parameters mean.

Now it's time to do stuff in our main class to generate the configuration for each virtual host. Roughly speaking, we will do the following: for each virtual host we will create/modify a file in */etc/apache2/sites-available*. We will use the apache2 tools *a2ensite* and *a2dissite* to enable or disable the virtual hosts according to the user configuration.

Let's create a private method called *_setVirtualHosts()* in our main class *src/EBox/Apache2.pm*::

    #!perl
    # Method: _setVirtualHosts
    #
    #       This method is used to set the virtual hosts
    #
    sub _setVirtualHosts
    {
            my ($self) = @_;

            my $mgr = EBox::Model::ModelManager->instance();
            my $model = $mgr->model('apache2/VirtualHosts');

            # Iterate over the virtual host table
            for my $id (@{$model->ids()}) {
                    my $row = $model->row($id);
                    my $name = $row->valueByName('name');
                    my $enabled = $row->valueByName('enabled');
                    my $outputFile = "/etc/apache2/sites-available/ebox-$name";
                    my @params = (name => $name);
                    # Write virtual host configuration file
                    $self->writeConfFile($outputFile, 'apache2/virtual-host.conf.mas', \@params);

                    # Create the document root directory if it does not exist
                                        my $row = $model->row($id);my $docRoot = "/var/www/$name";
                    unless ( -d $docRoot ) {
                            EBox::Sudo::root("mkdir $docRoot");
                    }
                    # Enable or disable the virtual host depending on the user configuration
                    if ($enabled) {
                            EBox::Sudo::root("a2ensite ebox-$name");
                    } else {
                            EBox::Sudo::root("a2dissite ebox-$name");
                    }
            }
    }

As we are modifying files, we have to let the framework know which files we are working with. You should remember, we have to implement the method *usedFiles()* in our main class. We have to return an array reference containing all these files. So the code will look like::

    #!perl
    # Method: usedFiles
    #
    #   Override EBox::ServiceModule::ServiceInterface::usedFiles
    #
    sub usedFiles
    {
            my $mgr = EBox::Model::ModelManager->instance();
            my $model = $mgr->model('apache2/VirtualHosts');

            my @usedFiles;
            for my $id (@{$model->ids()}) {
                    my $row = $model->row($id);
                    my $name = $row->valueByName('name');
                    push (@usedFiles, { file => "/etc/apache2/sites-available/ebox-$name",
                                       module => 'apache2',
                                       reason => __('To configure the virtual host')
                                      });
            }

            return \@usedFiles;
    }

The last change is actually calling the *_setVirtualHost()* method from *_setConf*::

    #!perl
    # Method: _setConf
    #
    #       Overrides EBox::Module::Service::_setConf
    #
    sub _setConf
    {
            my ($self) = @_;

            $self->_writeConfiguration();
            $self->_configureModules();
            $self->_setVirtualHosts();
    }

Let's recap all the changes that we need to make to *src/EBox/Apache2.pm*::

    #!perl
    # Copyright (C)
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

    # Class: EBox::Apache2 
    #
    #   TODO: Documentation

    package EBox::Apache2;

    use strict;
    use warnings;

    use base qw(EBox::GConfModule EBox::Model::ModelProvider
                EBox::ServiceModule::ServiceInterface);


    use EBox::Validate qw( :all );
    use EBox::Global;
    use EBox::Gettext;

    use EBox::Exceptions::InvalidData;
    use EBox::Exceptions::MissingArgument;
    use EBox::Exceptions::DataExists;
    use EBox::Exceptions::DataMissing;
    use EBox::Exceptions::DataNotFound;

    sub _create
    {
        my $class = shift;
        my $self = $class->SUPER::_create(name => 'apache2',
                printableName => __('Apache2'),
                domain => 'ebox-apache2',
                @_);
    }

    ## api functions

    # Overrides:
    #
    #       <EBox::Model::ModelProvider::modelClasses>
    sub modelClasses 
    {
        return [
            'EBox::Apache2::Model::Settings',
            'EBox::Apache2::Model::Modules',
            'EBox::Apache2::Model::VirtualHosts',
        ];
    }


    sub domain
    {
        return 'ebox-apache2';
    }

    # Method: actions
    #
    #   Override EBox::ServiceModule::ServiceInterface::actions
    #
    sub actions
    {
        return [];
    }


    # Method: usedFiles
    #
    #   Override EBox::ServiceModule::ServiceInterface::usedFiles
    #
    sub usedFiles
    {
        my $mgr = EBox::Model::ModelManager->instance();
            my $model = $mgr->model('apache2/VirtualHosts');
        
        my @usedFiles;
        for my $id (@{$model->ids()}) {
                my $row = $model->row($id);
                my $name = $row->valueByName('name');
                push (@usedFiles, { file => "/etc/apache2/sites-available/ebox-$name",
                   module => 'apache2',
                       reason => __('To configure the virtual host')
                  });
        }

            return \@usedFiles;
    }

    # Method: enableActions 
    #
    #   Override EBox::ServiceModule::ServiceInterface::enableActions
    #
    sub enableActions
    {
    }

    # Method: serviceModuleName 
    #
    #   Override EBox::ServiceModule::ServiceInterface::serviceModuleName
    #
    sub serviceModuleName
    {
        return 'apache2';
    }

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

    # Method: _setVirtualHosts
    #
    #   This method is used to set the virtual hosts
    #
    sub _setVirtualHosts
    {
            my ($self) = @_;

            my $mgr = EBox::Model::ModelManager->instance();
            my $model = $mgr->model('apache2/VirtualHosts');

            # Iterate over the virtual host table
            for my $id (@{$model->ids()}) {
                my $row = $model->row($id);
                my $name = $row->valueByName('name');
                my $enabled = $row->valueByName('enabled');
                my $outputFile = "/etc/apache2/sites-available/ebox-$name";
                my @params = (name => $name);
                # Write virtual host configuration file 
                $self->writeConfFile($outputFile, 'apache2/virtual-host.conf.mas', \@params);

                # Create the document root directory if it does not exist
                my $docRoot = "/var/www/$name";
                unless ( -d $docRoot ) {
                    EBox::Sudo::root("mkdir $docRoot");
                }
                # Enable or disable the virtual host depending on the user configuration
                if ($enabled) {
                                EBox::Sudo::root("a2ensite ebox-$name");
                        } else {
                                EBox::Sudo::root("a2dissite ebox-$name");
                        }
            }
    }


    # Method: _setConf
    #
    #       Overrides <EBox::Module::Service::_setConf>
    #
    sub _setConf
    {
            my ($self) = @_;

            $self->_writeConfiguration();
            $self->_configureModules();
            $self->_setVirtualHosts();
    }

    # Method: menu
    #
    #       Overrides EBox::Module method.
    #   
    #
    sub menu
    {
        my ($self, $root) = @_;

        my $folder = new EBox::Menu::Folder('name' => 'Apache2',
        'text' => __('Apache2'));

        my $settings = new EBox::Menu::Item(
        'url' => 'Apache2/View/Settings',
        'text' => __('Settings'));

        my $modules = new EBox::Menu::Item(
        'url' => 'Apache2/View/Modules',
        'text' => __('Modules'));

        my $virtualHosts = new EBox::Menu::Item(
        'url' => 'Apache2/View/VirtualHosts',
        'text' => __('Virtual Hosts'));
      

        $folder->add($settings);
        $folder->add($modules);
        $folder->add($virtualHosts);
        
        $root->add($folder);
    }

    1;
