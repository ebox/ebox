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
use strict;
use warnings;

package EBox::Squid::Model::ObjectPolicy;
use base 'EBox::Model::DataTable';
# Class:
#
#    EBox::Squid::Model::ObjectPolicy
#
#
#   It subclasses <EBox::Model::DataTable>
#

# eBox uses
use EBox;

use EBox::Exceptions::Internal;
use EBox::Gettext;
use EBox::Types::Text;
use EBox::Squid::Types::Policy;
use EBox::Squid::Types::TimePeriod;


# Group: Public methods

# Constructor: new
#
#       Create the new  model
#
# Overrides:
#
#       <EBox::Model::DataTable::new>
#
# Returns:
#
#       <EBox::Squid::Model::ObjectPolicy> - the recently
#       created model
#
sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    bless $self, $class;
    return $self;

}



# Method: _table
#
#
sub _table
{
  my @tableHeader =
    (
     new EBox::Types::Select(
         fieldName     => 'object',
         foreignModel  => \&objectModel,
         foreignField  => 'name',

         printableName => __('Object'),
         unique        => 1,
         editable      => 1,
         optional      => 0,
         ),
     new EBox::Squid::Types::Policy(
         fieldName     => 'policy',
         printableName => __('Policy'),
         ),
     new EBox::Squid::Types::TimePeriod(
                           fieldName => 'timePeriod',
                           printableName => __('Allowed time period'),
                           help          => __('Time period when the access is allowed. It is ignored with a deny policy'),
                           editable => 1,
                          ),

     new EBox::Types::HasMany (
      'fieldName' => 'groupPolicy',
      'printableName' => __('Group policy'),
      'foreignModel' => 'ObjectGroupPolicy',
      'view' => '/ebox/Squid/View/ObjectGroupPolicy',
      'backView' => '/ebox/Squid/View/ObjectGroupPolicy',
      'size' => '1',
     ),
     new EBox::Types::Select(
                             fieldName => 'filterGroup',
                             printableName => __('Filter profile'),

                             foreignModel  => \&filterGroupModel,
                             foreignField  => 'name',
                             
                             defaultValue  => 'default',
                             editable      => 1,
                            ),
    );

  my $dataTable =
  {
      tableName          => name(),
      pageTitle          => __('Object Policies'),
      printableTableName => __('List of objects'),
      HTTPUrlView        => 'Squid/View/ObjectPolicy',
      modelDomain        => 'Squid',
      'defaultController' => '/ebox/Squid/Controller/ObjectPolicy',
      'defaultActions' => [
          'add', 'del',
      'editField',
      'changeView',
      'move',
          ],
      tableDescription   => \@tableHeader,
      class              => 'dataTable',
      order              => 1,
      rowUnique          => 1,
      automaticRemove    => 1,
      printableRowName   => __("object's policy"),
      help               => __("Here you can establish a custom policy per network object"),
      messages           => {
          add => __(q{Added object's policy}),
          del =>  __(q{Removed object's policy}),
          update => __(q{Updated object's policy}),
      },
  };

}

sub objectModel
{
    my $objects = EBox::Global->getInstance()->modInstance('objects');
    return $objects->{'objectModel'};
}

sub filterGroupModel
{
    my ($self) = @_;
    my $sq = EBox::Global->modInstance('squid');
    return $sq->model('FilterGroup');
}


sub name
{
    return 'ObjectPolicy';
}

sub validateTypedRow
{
  my ($self, $action, $params_r, $actual_r) = @_;
  $self->_checkPolicyWithTransProxy($params_r, $actual_r);
  $self->_checkPolicyWithTimePeriod($params_r, $actual_r);
  $self->_checkPolicyWithGroupsPolicy($params_r, $actual_r);
  $self->_checkFilterProfile($params_r, $actual_r);
}


sub _checkPolicyWithTransProxy
{
  my ($self, $params_r, $actual_r) = @_;

  my $squid = EBox::Global->modInstance('squid');
  if (not $squid->transproxy()) {
    return;
  }


  my $pol = exists $params_r->{policy} ?
                     $params_r->{policy}:
                     $actual_r->{policy} ;

  if ($pol->usesAuth()) {
    throw EBox::Exceptions::External(
       __('Authorization policy is not compatible with transparent proxy mode')
                                    );
  }
}

sub _checkPolicyWithTimePeriod
{
  my ($self, $params_r, $actual_r) = @_;

  my $policy = exists $params_r->{policy} ?
                     $params_r->{policy} :
                     $actual_r->{policy} ;

  my $time = exists $params_r->{timePeriod} ?
                     $params_r->{timePeriod} :
                     $actual_r->{timePeriod} ;

  if ($time->isAllTime()) {
      return;
  }

  if ($policy->usesFilter()) {
      throw EBox::Exceptions::External(
         __('Filter policies are incompatible with restricted time periods')
                                      );
  }

}



sub _checkPolicyWithGroupsPolicy
{
  my ($self, $params_r, $actual_r) = @_;


  my $policy = exists $params_r->{policy} ?
                     $params_r->{policy} :
                     $actual_r->{policy} ;

  my $usesAuth = $policy->usesAuth();
  if ($usesAuth) {
      return;
  }

  my $groupPolicyElement = $actual_r->{groupPolicy};
  my $groupPolicy        = $groupPolicyElement->foreignModelInstance();
  if ($groupPolicy->size() > 0) {
      throw EBox::Exceptions::External(
   __('You cannot choose a policy without authorization if you have any group policy')
                                      );
  }

}


sub _checkFilterProfile
{
  my ($self, $params_r, $actual_r) = @_;

  my $filterGroup = exists $params_r->{filterGroup} ?
                     $params_r->{filterGroup} :
                     $actual_r->{filterGroup} ;
  if ($filterGroup->value() eq 'default') {
      # default group is ocmpatible with all policies
      return;
  }
  
  my $policyElement = exists $params_r->{policy} ?
                     $params_r->{policy} :
                     $actual_r->{policy} ;

  my $policy = $policyElement->value();
  if ($policy ne 'filter') {
      throw EBox::Exceptions::External(
   __(q{You can only use a custom profile with the 'Filter' policy})
                                      );
  }

}


sub objectsPolicies
{
  my ($self) = @_;

  my $objectMod = EBox::Global->modInstance('objects');

  my @obsPol = map {
      my $row = $self->row($_);

      my $obj           = $row->valueByName('object');
      my $addresses     = $objectMod->objectAddresses($obj);

      my $policy        = $row->elementByName('policy');
      my $auth          = $policy->usesAuth();
      my $allowAll      = $policy->usesAllowAll();
      my $filter        = $policy->usesFilter();

      my $timePeriod    = $row->elementByName('timePeriod');
      my $groupPolicy   = $row->subModel('groupPolicy');

    if (@{ $addresses }) {
      my $obPol = {
                   object    => $obj,
                   addresses => $addresses,
                   auth      => $auth,
                   allowAll  => $allowAll,
                   filter    => $filter,
                  };

      if (not $timePeriod->isAllTime) {
          if (not $timePeriod->isAllWeek()) {
              $obPol->{timeDays} = $timePeriod->weekDays();
          }

          my $hours = $timePeriod->hourlyPeriod();
          if ($hours) {
              $obPol->{timeHours} = $hours;
          }
      }

      $obPol->{groupsPolicies} = $groupPolicy->groupsPolicies();

      $obPol;
    }
    else {
      ()
    }

  } @{ $self->ids()  };

  return \@obsPol;
}




sub objectsFilterGroups
{
    my ($self) = @_;

  my %filterGroupIdByRowId = %{ $self->filterGroupModel->idByRowId() };

    my $objectMod = EBox::Global->modInstance('objects');

    my @filterGroups;
    # object polices have priority by position in table
    foreach my $id (@{ $self->ids()  }) {
        my $row = $self->row($id);
        my $filterGroup = $row->valueByName('filterGroup');
        if ($filterGroup eq 'default') {
            next;
        }
        if ($row->valueByName('policy') ne 'filter') {
            EBox::debug(
"Object row with id $id has a custom filter group and a policy that is not 'filter'"
                       );
            next;
        }

        my $obj           = $row->valueByName('object');
        my @addresses = @{ $objectMod->objectAddresses($obj)  };
        foreach my $address (@addresses) {
            # remove /32 netmask froms hosts addresses
            $address =~ s{/32$}{};
            push @filterGroups, { 
                                 address=> $address, 
                                 group  => $filterGroupIdByRowId{$filterGroup}  
                                };
        }
    }

    return \@filterGroups;
}


sub existsAuthObjects
{
  my ($self) = @_;

  foreach my $id ( @{ $self->ids() } )  {
    my $row = $self->row($id);
    my $obPolicy = $row->valueByName('policy');
    my $groupPolicy = $row->subModel('groupPolicy');

    return 1 if $obPolicy eq 'auth';
    return 1 if $obPolicy eq 'authAndFilter';

    return 1 if @{ $groupPolicy->groupsPolicies() } > 0;
  }

  return undef;
}





sub existsFilteredObjects
{
  my ($self) = @_;

  foreach my $id ( @{ $self->ids() } )  {
    my $obPolicy = $self->row($id)->valueByName('policy');
    return 1 if $obPolicy eq 'filter';
    return 1 if $obPolicy eq 'authAndFilter';
  }

  return undef;
}

sub _objectsByPolicy
{
    my ($self, $policy) = @_;

    EBox::Squid::Types::Policy->checkPolicy($policy);


    my @objects = map {
        my $row = $self->row($_);
        my $obPolicy = $row->valueByName('policy');
        ($obPolicy eq $policy) ? $row->valueByName('object') : ()

    } @{ $self->ids()  };



    return \@objects;
}

sub _objectHasPolicy
{
    my ($self, $object, $policy) = @_;

    EBox::Squid::Types::Policy->checkPolicy($policy);


    my $objectRow = $self->_findRowByObjectName($object);
    if (not defined $objectRow) {
        throw EBox::Exceptions::External('{o} does not exists', o => $object );
    }

    return $objectRow->valueByName('policy') eq $policy;
}






# Method: isUnfiltered
#
#       Checks if a given object is set as unfiltered
#
# Parameters:
#
#       object - object name
#
# Returns:
#
#       boolean - true if it's set as unfiltered, otherwise false
sub isUnfiltered # ($object)
{
    my ($self, $object) = @_;
    return $self->_objectHasPolicy($object, 'allow') or
           $self->_objectHasPolicy($object, 'auth');
}




# Method: isBanned
#
#       Checks if a given object is banned
#
# Parameters:
#
#       object - object name
#
# Returns:
#
#       boolean - true if it's set as banned, otherwise false
sub isBanned # ($object)
{
  my ($self, $object) = @_;
  $self->_objectHasPolicy($object, 'deny');
}


sub _findRowByObjectName
{
    my ($self, $objectName) = @_;

    my $objectModel = $self->objectModel();
    my $objectRowId = $objectModel->findId(name => $objectName);

    my $row = $self->findRow(object => $objectRowId);

    return $row;
}


sub existsPoliciesForGroup
{
    my ($self, $group) = @_;
    foreach my $id (@{ $self->ids() }) {
        my $row = $self->row($id);
        my $groupPolicy   = $row->subModel('groupPolicy');
        if ($groupPolicy->existsPoliciesForGroup($group)) {
            return 1;
        }
    }

    return 0;
}

sub delPoliciesForGroup
{
    my ($self, $group) = @_;
    foreach my $id (@{ $self->ids() }) {
        my $row = $self->row($id);
        my $groupPolicy   = $row->subModel('groupPolicy');
        $groupPolicy->delPoliciesForGroup($group)
    }
}

sub precondition
{
    my ($self) = @_;
    my $objects = EBox::Global->modInstance('objects');

    return @{ $objects->objects() } > 0;
}

sub preconditionFailMsg
{
    return __x(
'There are no network objects in the system. {open}Create{close} at least one object if you want to set a object policy',
open => q{<a href='/ebox/Objects/View/ObjectTable'>},
close => q{</a>},
);
}

1;

