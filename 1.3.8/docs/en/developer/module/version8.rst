===============================
Version 0.8: complex validation
===============================

There was something we missed when we introduced the *ServerAliases* model. Because we set the *unique* attribute of the domain names to 1, the user cannot introduce the same alias twice in the same table. However, it does not check if the alias has been used in other virtual host or in a virtual host itself. The same happens when a virtual host is added, the framework does not check automatically if the domain name is used in some virtual host alias.

Data model
==========

We will add code to our model to carry out the necessary checks. We will implement the method *validateTypedRow* which is called every time a new row is added or an existing row is modified.

This is the method you must add to *src/EBox/Model/ServerAliases.pm*::

    #!perl
    # Method: validateTypedRow
    #
    #       Override <EBox::Model::DataTable::validateTypedRow>
    #
    #       Check if this domain name is used by any other virtual host
    #
    # Arguments:
    #
    #     action - String containing the action to be performed
    #               after validating this row.
    #               Current options: 'add', 'update'
    #     params - hash ref containing fields names and their values
    #
    # Returns:
    #
    #    Nothing
    #
    # Exceptions:
    #
    #     You must throw an exception whenever a field value does not
    #     fulfill your requirements
    #
    sub validateTypedRow
    {
            my ($self, $action, $params) = @_;

            return unless (exists $params->{name});
            my $newName = $params->{name}->value();

            my $parentModel = $self->parent();
            return unless ($parentModel);

            # Keep the current directory
            my $directory = $self->directory();

            for my $id (@{$parentModel->ids()}) {
                    my $row = $parantModel->row($id);
                    my $virtualHost = $row->valueByName('name');
                    if ($virtualHost eq $newName) {
                            my $virtEx = __x('There is already a virtual host named {name}',
                                    name => $newName);
                            throw EBox::Exceptions::External($virtEx);
                    }
                    for my $subId (@{$row->subModel('aliases')->ids()}) {
                            my $subRow = $row->subModel('aliases')->row($subId);
                            if ($subRow->valueByName('name') eq $newName) {
                                    my $virtEx = __x('There is already a server alias named {name} '
                                                     . 'in virtual host {virtual}',
                                                      name => $newName,
                                                      virtual => $virtualHost);
                                    throw EBox::Exceptions::External($virtEx);
                            }
                    }
            }

            # Restore the directory
            $self->setDirectory($directory);
    }

Let's do a walkthrough the above code.

The very first thing we do after fetching the parameters is returning from the method if the field *name* does not exists. If it does not exists that means that we are not either adding a new row or the user has edited a row but he has not modified the name.

We fetch the *parent* model becasue we want to iterate over all the virtual hosts and aliases. We could have used the method model from *EBox::Model::!ModelManager* to retrieve the model but this approach will show us how we can move through the hierarchical structure that makes up models and submodels and how we can easily identify which virtual host our alias belongs to.

The next important part is::

    #!perl
         # Keep the current directory
         my $directory = $self->directory();

         #...................................

         # Restore the directory
         $self->setDirectory($directory);

What we do above is save the current directory of our model and restore it. This has to be done everytime you iterate over a parent model from one of the following methods:

* addRow
* addTypedRow
* validateTypedRow


The loop is pretty simple, it just checks if the new domain name already exists by iterating through the entire model and submodel hierarchy as we learnt in version 0.7.

Finally, we have to implement a similar method in *src/EBox/Model/VirtualHosts*. It's basically the same code without the save and restore procedure::

    #!perl
    # Method: validateTypedRow
    #
    #       Override <EBox::Model::DataTable::validateTypedRow>
    #
    #       Check if this domain name is used by any other virtual host
    #
    # Arguments:
    #
    #     action - String containing the action to be performed
    #               after validating this row.
    #               Current options: 'add', 'update'
    #     params - hash ref containing fields names and their values
    #
    # Returns:
    #
    #    Nothing
    #
    # Exceptions:
    #
    #     You must throw an exception whenever a field value does not
    #     fulfill your requirements
    #
    sub validateTypedRow
    {
            my ($self, $action, $params) = @_;

            return unless (exists $params->{name});
            my $newName = $params->{name}->value();

            for my $id (@{$self->ids()}) {
                    my $row = $self->row($id);
                    my $virtualHost = $row->valueByName('name');
                    if ($virtualHost eq $newName) {
                            my $virtEx = __x('There is already a virtual host named {name}',
                                    name => $newName);
                            throw EBox::Exceptions::External($virtEx);
                    }
                    for my $subId (@{$row->subModel('aliases')->ids()}) {
                            my $subRow = $row->subModel('aliases')->row($subId);
                            if ($subRow->valueByName('name') eq $newName) {
                                    my $virtEx = __x('There is already a server alias named {name} '
                                                     . 'in virtual host {virtual}',
                                                      name => $newName,
                                                      virtual => $virtualHost);
                                    throw EBox::Exceptions::External($virtEx);
                            }
                    }
            }
    }
