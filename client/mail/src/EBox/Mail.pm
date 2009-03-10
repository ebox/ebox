# Copyright (C) 2005 Warp Netwoks S.L., DBS Servicios Informaticos S.L.
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
# You should have received a copy of the GNU General Public Licensema
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package EBox::Mail;

use strict;
use warnings;


use base qw(EBox::Module::Service EBox::LdapModule EBox::ObjectsObserver
            EBox::Model::ModelProvider EBox::Model::CompositeProvider
            EBox::FirewallObserver EBox::LogObserver
            EBox::Report::DiskUsageProvider 
           );

use EBox::Sudo qw( :all );
use EBox::Validate qw( :all );
use EBox::Gettext;
use EBox::Config;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::MailVDomainsLdap;
use EBox::MailUserLdap;
use EBox::MailAliasLdap;
use EBox::MailLogHelper;
use EBox::MailFirewall;
use EBox::Mail::Greylist;
use EBox::Service;

use EBox::Exceptions::InvalidData;
use EBox::Dashboard::ModuleStatus;
use EBox::ServiceManager;


use Proc::ProcessTable;
use Perl6::Junction qw(all);

use constant MAILMAINCONFFILE                   => '/etc/postfix/main.cf';
use constant MAILMASTERCONFFILE                 => '/etc/postfix/master.cf';
use constant MASTER_PID_FILE                    => '/var/spool/postfix/pid/master.pid';

use constant DOVECOT_CONFFILE                   => '/etc/dovecot/dovecot.conf';
use constant DOVECOT_LDAP_CONFFILE              =>  '/etc/dovecot/dovecot-ldap.conf';

use constant MAILINIT                           => 'postfix';

use constant BYTES                              => '1048576';

use constant DOVECOT_SERVICE                    => 'ebox.dovecot';

use constant SASL_PASSWD_FILE                   => '/etc/postfix/sasl_passwd';

use constant SERVICES => ('active', 'filter', 'pop', 'imap', 'sasl');

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(
                                      name => 'mail',
                                      printableName =>__('mail'),
                                      domain => 'ebox-mail',
                                      @_
    );

    $self->{vdomains} = new EBox::MailVDomainsLdap;
    $self->{musers} = new EBox::MailUserLdap;
    $self->{malias} = new EBox::MailAliasLdap;
    $self->{greylist} = new EBox::Mail::Greylist;

    bless($self, $class);
    return $self;
}

sub domain
{
    return 'ebox-mail';
}

sub greylist
{
    my ($self) = @_;
    return $self->{greylist};
}

# neccesary for daemon precondition
sub greylistIsEnabled
{
    my ($self) = @_;
    return $self->greylist()->isEnabled();
}



# Method: actions
#
#       Override EBox::Module::Service::actions
#
sub actions
{
    return [
            {
              'action' => __('Generate mail aliases'),
              'reason' =>
                __x('eBox will execute {cmd}', cmd => '/usr/sbin/postalias /etc/aliases'),

              'module' => 'mail'
            },
            {
              'action' => __('Add LDAP schemas'),
              'reason' => __(
                          'eBox will add two LDAP schemas: authldap.schema and '
                            .'eboximail.schema.'
              ),
              'module' => 'mail'
            }
    ];
}

# Method: usedFiles
#
#       Override EBox::Module::Service::files
#
sub usedFiles
{
    my ($self) = @_;

    my @greylistFiles =   @{ $self->greylist()->usedFiles() };

    return [
            {
              'file' => MAILMAINCONFFILE,
              'reason' => __('To configure postfix'),
              'module' => 'mail'
            },
            {
              'file' => MAILMASTERCONFFILE,
              'reason' => __(
                         'To define how client programs connect to services in '
                           .' postfix'
              ),
              'module' => 'mail'
            },
            {
              'file' => DOVECOT_CONFFILE,
              'reason' => __('To configure dovecot'),
              'module' => 'mail'
            },
            {
              'file' => DOVECOT_LDAP_CONFFILE,
              'reason' =>  __('To configure dovecot to authenticate against LDAP'),
              'module' => 'mail'
            },
            {
              'file' => '/etc/ldap/slapd.conf',
              'reason' => __('To add the LDAP schemas used by eBox mail'),
              'module' => 'users'
            } ,
            {
              'file' => SASL_PASSWD_FILE,
              'reason' => __('To configure smart host authentication'),
              'module' => 'mail'
            },
            @greylistFiles
    ];
}

# Method: enableActions
#
#       Override EBox::Module::Service::enableActions
#
sub enableActions
{
    root(EBox::Config::share() . '/ebox-mail/ebox-mail-enable');
}

#  Method: enableModDepends
#
#   Override EBox::Module::Service::enableModDepends
#
sub enableModDepends
{
    my ($self) = @_;
    my @depends =  ('network', 'users');

    if ($self->service('filter') ) {
        my $name = $self->externalFilter();
        if ($name ne 'custom') { # we cannot get deps from a custom module
            my $filterMod = $self->_filterAttr($name, 'module', 0);
            if ($filterMod) {
                push @depends, $filterMod;
            }
        }
    }

    return \@depends;
}

# Method: modelClasses
#
# Overrides:
#
#    <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
            'EBox::Mail::Model::SMTPAuth',
            'EBox::Mail::Model::SMTPOptions',
            'EBox::Mail::Model::RetrievalServices',
            'EBox::Mail::Model::ObjectPolicy',
            'EBox::Mail::Model::VDomains',
            'EBox::Mail::Model::ExternalFilter',

            'EBox::Mail::Model::Dispatcher::Mail',

            'EBox::Mail::Model::GreylistConfiguration',
           ];
}


# Method: compositeClasses
#
# Overrides:
#
#    <EBox::Model::CompositeProvider::compositeClasses>
#
sub compositeClasses
{
    return [
            'EBox::Mail::Composite::ServiceConfiguration',
            'EBox::Mail::Composite::General',
           ];
}


# Method: _getIfacesForAddress
#
#  This method returns all interfaces which ip address belongs
#
# Parameters:
#
#               ip - The IP address
#
# Returns:
#
#               array ref - with all interfaces
sub _getIfacesForAddress
{
    my ($self, $ip) = @_;

    my $net = EBox::Global->modInstance('network');
    my @ifaces = ();

    # check if it is a loopback address
    if (EBox::Validate::isIPInNetwork('127.0.0.1', '255.0.0.0', $ip)) {
        return ['lo'];
    }

    foreach my $iface (@{$net->InternalIfaces()}) {
        foreach my $addr (@{$net->ifaceAddresses($iface)}) {
            if (isIPInNetwork($addr->{'address'}, $addr->{'netmask'}, $ip)) {
                push(@ifaces, $iface);
            }
        }
    }

    return \@ifaces;
}

# Method: _setMailConf
#
#  This method creates all configuration files from gconf data.
#
sub _setMailConf
{
    my ($self) = @_;

    my $daemonUid = getpwnam('daemon');
    my $daemonGid = getgrnam('daemon');
    my $perm      = '0640';


    my $daemonMode = {
                      uid => $daemonUid,
                      gid => $daemonGid,
                      mode => $perm
                     };

    my @array = ();
    my $users = EBox::Global->modInstance('users');
    my $ldap = EBox::Ldap->instance();
    my $allowedaddrs = "127.0.0.0/8";

    foreach my $addr (@{ $self->allowedAddresses }) {
        $allowedaddrs .= " $addr";
    }

    push(@array, fqdn => $self->_fqdn());
    push(@array, 'ldapi', $self->{vdomains}->{ldap}->ldapConf->{ldap});
    push(@array, 'vdomainDN', $self->{vdomains}->vdomainDn());
    push(@array, 'relay', $self->relay());
    push(@array, 'relayAuth', $self->relayAuth());
    push(@array, 'maxmsgsize', ($self->getMaxMsgSize() * $self->BYTES));
    push(@array, 'allowed', $allowedaddrs);
    push(@array, 'aliasDN', $self->{malias}->aliasDn());
    push(@array, 'vmaildir', $self->{musers}->DIRVMAIL);
    push(@array, 'usersDN', $users->usersDn());
    push(@array, 'uidvmail', $self->{musers}->uidvmail());
    push(@array, 'gidvmail', $self->{musers}->gidvmail());
    push(@array, 'sasl', $self->service('sasl'));
    push(@array, 'smtptls', $self->tlsSmtp());
    push(@array, 'popssl', $self->pop3s());
    push(@array, 'imapssl', $self->imaps());
    push(@array, 'ldap', $ldap->ldapConf());
    push(@array, 'filter', $self->service('filter'));
    push(@array, 'ipfilter', $self->ipfilter());
    push(@array, 'portfilter', $self->portfilter());
    # greylist parameters
    my $greylist = $self->greylist();
    push(@array, 'greylist',     $greylist->isEnabled() );
    push(@array, 'greylistAddr', $greylist->address());
    push(@array, 'greylistPort', $greylist->port());
    $self->writeConfFile(MAILMAINCONFFILE, "mail/main.cf.mas", \@array);

    @array = ();
    push(@array, 'smtptls', $self->tlsSmtp);
    push(@array, 'filter', $self->service('filter'));
    push(@array, 'fwport', $self->fwport());
    push(@array, 'ipfilter', $self->ipfilter());
    $self->writeConfFile(MAILMASTERCONFFILE, "mail/master.cf.mas", \@array);

    @array = ();
    push(@array, 'uid', scalar(getpwnam('ebox')));
    push(@array, 'gid', scalar(getgrnam('ebox')));
    push(@array, 'protocols' , $self->_retrievalProtocols());


    $self->writeConfFile(DOVECOT_CONFFILE, "mail/dovecot.conf.mas",\@array);

    @array = ();
    push @array, ('usersDn', $users->usersDn());
    $self->writeConfFile(DOVECOT_LDAP_CONFFILE, "mail/dovecot-ldap.conf.mas",\@array);

    # greylist configuration files
    $greylist->writeConf();

    $self->writeConfFile(SASL_PASSWD_FILE,
                         'mail/sasl_passwd.mas',
                         [
                          relayHost => $self->relay(),
                          relayAuth => $self->relayAuth(),
                         ],
                         {
                          uid  => 0,
                          gid  => 0,
                          mode => '0600',
                         }
                        );
    my $manager = new EBox::ServiceManager;
    # Do not run postmap if we can't overwrite SASL_PASSWD_FILE
    unless ($manager->skipModification('mail', SASL_PASSWD_FILE)) {
        EBox::Sudo::root('/usr/sbin/postmap ' . SASL_PASSWD_FILE);
    }
}


sub _retrievalProtocols
{
    my ($self) = @_;

    my $model = $self->model('RetrievalServices');
    return $model->activeProtocos();
}

sub pop3s
{
    my ($self) = @_;

    my $model = $self->model('RetrievalServices');
    return $model->pop3sValue();
}


sub imaps
{
    my ($self) = @_;

    my $model = $self->model('RetrievalServices');
    return $model->imapsValue();
}



sub _fqdn
{
    my $fqdn = `hostname --fqdn`;
    if ($? != 0) {
        throw EBox::Exceptions::Internal(
'eBox was unable to get the full qualified domain name (FQDN) for his host/'
              .'Please, check than your resolver and /etc/hosts file are properly configured.'
          );
    }

    return $fqdn;
}



sub isGreylistEnabled
{
    my ($self) = @_;
    return $self->greylist()->isEnabled();
}

#  Method: _daemons

#   Override <EBox::Module::Service::_daemons>
#
sub _daemons
{
    my ($self) = @_;

    my $daemons = [
        {
            'name' => MAILINIT,
            'type' => 'init.d',
            'pidfile' => MASTER_PID_FILE,
        },
        {
         name => DOVECOT_SERVICE,
         precondition => \&_dovecotService,
        },

#         {
#             'name' => POPINIT,
#             'type' => 'init.d',
#             'pidfile' => POPPIDFILE,
#             'precondition' => \&isPopEnabled
#         },
#         {
#             'name' => IMAPINIT,
#             'type' => 'init.d',
#             'pidfile' => IMAPPIDFILE,
#             'precondition' => \&isImapEnabled
#         },
#         {
#             'name' => AUTHDAEMONINIT,
#             'type' => 'init.d',
#             'pidfile' => AUTHDAEMONPIDFILE
#         },
#         {
#             'name' => AUTHLDAPINIT,
#             'type' => 'init.d',
#             'pidfile' => AUTHLDAPPIDFILE
#         },
    ];

    my $greylist_daemon = $self->greylist()->daemon();
    $greylist_daemon->{'precondition'} = \&isGreylistEnabled;
    push(@{$daemons}, $greylist_daemon);

    return $daemons;
}

# Method: isRunning
#
#  This method returns if the service is running
#
# Parameter:
#
#               service - a string with a service name. It could be:
#                       active for smtp service
#                       pop for pop service
#                       imap for imap service
#
# Returns
#
#               bool - true if the service is running, false otherwise
sub isRunning
{
    my ($self, $service) = @_;

    if (not defined($service)) {
        if ($self->_dovecotService()) {
            if ($self->_dovecotIsRunning()) {
                return 1;
            } elsif ($self->greylist()->isRunning()) {
                return 1;
            }

            return undef;
        }

        return $self->_postfixIsRunning();
    } elsif ($service eq 'active') {
        return $self->_postfixIsRunning();
    } elsif ($service eq 'pop') {
        return $self->_dovecotIsRunning();
    } elsif ($service eq 'imap') {
        return $self->_dovecotIsRunning();
    }
}





sub _dovecotIsRunning
{
    my ($self) = @_;
    return EBox::Service::running(DOVECOT_SERVICE);
}

sub _postfixIsRunning
{
    my ($self, $service) = @_;
    my $t = new Proc::ProcessTable;
    foreach my $proc (@{$t->table}) {
        ($proc->fname eq 'master') and return 1;
    }
    return undef;
}

# Method: externalFiltersFromModules
#
#  return a list with all the external filters provided by eBox's modules
#
sub externalFiltersFromModules
{
    my ($self) = @_;

    my $global = EBox::Global->getInstance;
    my %filters = map {
        my ($name, $attrs) = $_->mailFilter();
        defined $name ? ($name => $attrs) : ();
    } @{ $global->modInstancesOfType('EBox::Mail::FilterProvider') };

    return \%filters;

}



#  Method : externalFilter
#
#  return ther name of the external filter used or the name 'custom' in case
#  user's custom settings are in use
sub externalFilter
{
    my ($self) = @_;
    my $filterModel = $self->model('ExternalFilter');
    return $filterModel->externalFilter();
}

sub _assureCustomFilter
{
    my ($self) = @_;
    if ($self->externalFilter ne 'custom') {
        throw EBox::Exceptions::External(
                    __('Cannot change this parameter for a non-custom filter'));
    }

}

sub _filterAttr
{
    my ($self, $name, $attr, $onlyActive) = @_;
    defined $onlyActive
      or$onlyActive = 1;

    my $filters_r = $self->externalFiltersFromModules();

    exists $filters_r->{$name}
      or throw EBox::Exceptions::External(
        __(
'The mail filter does not exist. Please set another mail filter or disable it'
        )
      );

    my $value =  $filters_r->{$name}->{$attr};
    defined $value
      or throw EBox::Exceptions::Internal(
                                "Cannot found attribute $attr in filter $name");

    return $value;
}

sub _assureFilterIsActive
{
    my ($self, $name) = @_;
    my $filters_r = $self->externalFiltersFromModules();

    exists $filters_r->{$name}
      or throw EBox::Exceptions::External(
        __(
'The mail filter does not exist. Please set another mail filter or disable it'
        )
      );

    if (not $filters_r->{$name}->{active}) {
        throw EBox::Exceptions::External(
            __(
'The mail filter $name is not active. Please set another mail filter or disable it'
            )
        );
    }
}

# returns wether we must use the filter attr instead of the stored in the
# module's cponfgiuration
sub _useFilterAttr
{
    my ($self) = @_;

    if (not $self->service('filter')) {
        return 0;
    }

    if ($self->externalFilter() eq 'custom') {
        return 0;
    }

    return 1;
}


# Method: ipfilter
#
#  This method returns the ip of the external filter
#
sub ipfilter
{
    my $self = shift;

    if ($self->_useFilterAttr) {
        return $self->_filterAttr($self->externalFilter, 'address');
    }

    my $filterModel = $self->model('ExternalFilter');
    return $filterModel->ipfilter();
}



# Method: portfilter
#
#  This method returns the port where the mail filter listen
#
sub portfilter
{
    my $self = shift;

    if ($self->_useFilterAttr) {
        return $self->_filterAttr($self->externalFilter, 'port');
    }

    my $filterModel = $self->model('ExternalFilter');
    return $filterModel->portfilter();
}


# Method: fwport
#
#  This method returns the port where forward all messages from external filter
#
sub fwport
{
    my $self = shift;

    if ($self->_useFilterAttr) {
        return $self->_filterAttr($self->externalFilter, 'forwardPort');
    }

    my $filterModel = $self->model('ExternalFilter');
    return $filterModel->fwport();
}


# Method: relay
#
#  This method returns the ip address of the smarthost if set
#
sub relay
{
    my ($self) = @_;
    my $smtpOptions = $self->model('SMTPOptions');
    return $smtpOptions->smarthost();
}


sub relayAuth
{
    my ($self) = @_;
    my $smtpOptions = $self->model('SMTPOptions');
    my $auth = $smtpOptions->row()->elementByName('smarthostAuth');

    my $selectedType = $auth->selectedType();
    if ($selectedType eq 'userandpassword') {
        return $auth->value();
    }

    return undef;
}


# Method: getMaxMsgSize
#
#  This method returns the maximum message size
#
sub getMaxMsgSize
{
    my ($self) = @_;
    my $smtpOptions = $self->model('SMTPOptions');
    return $smtpOptions->maxMsgSize();
}




# Method: tlsSmtp
#
#  This method returns if tls on smtp is active
#
sub tlsSmtp
{
    my ($self) = @_;

    my $smtpAuth = $self->model('SMTPAuth');
    return $smtpAuth->tls();
}


sub _sslRetrievalServices
{
    my ($self) = @_;
    my $retrievalServices = $self->model('RetrievalServices');
    return $retrievalServices->pop3sValue() or $retrievalServices->imapsValue();
}

#
# Method: allowedAddresses
#
#  Returns the list of allowed objects to relay mail.
#
# Returns:
#
#  array ref - holding the objects
#
sub allowedAddresses
{
    my ($self)  = @_;
    my $objectPolicy = $self->model('ObjectPolicy');
    return $objectPolicy->allowedAddresses();
}

#
# Method: isAllowed
#
#  Checks if a given object is allowed to relay mail.
#
# Parameters:
#
#  object - object name
#
# Returns:
#
#  boolean - true if it's set as allowed, otherwise false
#
sub isAllowedxb
{
    my ($self, $object)  = @_;
    my $objectPolicy = $self->model('ObjectPolicy');
    return $objectPolicy->isAllowed($object);
}



#
# Method: freeObject
#
#  This method unsets a new allowed object list without the object passed as
#  parameter
#
# Parameters:
#               object - The object to remove.
#
sub freeObject # (object)
{
    my ($self, $object) = @_;
    $object or 
        throw EBox::Exceptions::MissingArgument('object');

    my $objectPolicy = $self->model('ObjectPolicy');
    $objectPolicy->freeObject($object);

}

# Method: usesObject
#
#  This methos method returns if the object is on allowed list
#
# Returns:
#
#               bool - true if the object is in allowed list, false otherwise
#
sub usesObject # (object)
{
    my ($self, $object) = @_;
    if ($self->isAllowed($object)) {
        return 1;
    }
    return undef;
}

# Function: usesPort
#
#       Implements EBox::FirewallObserver interface
#
sub usesPort # (protocol, port, iface)
{
    my ($self, $protocol, $port, $iface) = @_;

    my %srvpto = (
                  'active' => 25,
                  'pop'         => 110,
                  'imap'        => 143,
    );

    foreach my $mysrv (keys %srvpto) {
        return 1 if (($port eq $srvpto{$mysrv}) and ($self->service($mysrv)));
    }

    return undef;
}

sub firewallHelper
{
    my $self = shift;
    if ($self->anyDaemonServiceActive()) {
        return new EBox::MailFirewall();
    }
    return undef;
}





sub _dovecotService
{
    my ($self) = @_;


    # if main service is disabled, dovecot too!
    if (not $self->service('active')) {
        return undef;
    }

    if ( @{ $self->_retrievalProtocols } > 0 ) {
        return 1;
    }

    # dovecot is also needed for smtp auth
    if ($self->saslService()) {
        return 1;
    }


    return undef;

}



sub _regenConfig
{
    my ($self) = @_;

    if ($self->service) {
        $self->_setMailConf;
        my $vdomainsLdap = new EBox::MailVDomainsLdap;
        $vdomainsLdap->regenConfig();

    }

    $self->greylist()->writeUpstartFile();
    $self->_enforceServiceState();

}



#
# Method: service
#
#  Returns the state of the service passed as parameter
#
# Parameters:
#
#  service - the service (default: 'active' (main service))
#
# Returns:
#
#  boolean - true if it's active, otherwise false
#
sub service
{
    my ($self, $service) = @_;
    defined($service) or $service = 'active';
    $self->_checkService($service);

    if ($service eq 'active') {
        return $self->isEnabled();
    } 
    elsif ($service eq 'sasl') {
        return $self->saslService();
    }
    elsif ($service eq 'pop') { # that e
        return $self->model('RetrievalServices')->pop3Value() or
            $self->model('RetrievalServices')->pop3sValue();
    } 
    elsif ($service eq 'imap') {
        return $self->model('RetrievalServices')->imapValue() or
            $self->model('RetrievalServices')->imapsValue();
    }
    elsif ($service eq 'filter') {
        return $self->externalFilter() ne 'none';
    }
    else {
        throw EBox::Exceptions::Internal("Unknown service $service");
    } 
}


sub saslService
{
    my ($self) = @_;

    my $smtpAuth = $self->model('SMTPAuth');
    return $smtpAuth->sasl();
}


#
# Method: anyDaemonServiceActive
#
#  Returns if any service which a indendent daemon is active
#
# Returns:
#
#  boolean - true if any is active, otherwise false
#
sub anyDaemonServiceActive
{
    my ($self) = @_;
    my @services = ('active', 'pop', 'imap');

    foreach (@services) {
        return 1 if $self->service($_);
    }

    return undef;
}

sub _checkService
{
    my ($self, $service) = @_;

    if ($service ne all(SERVICES)) {
        throw EBox::Exceptions::Internal("Inexistent service $service");
    }
}

# LdapModule implmentation
sub _ldapModImplementation
{
    my $self;

    return new EBox::MailUserLdap();
}


sub notifyAntispamACL
{
    my ($self) = @_;

    # greylist must be notified of antispam changes
    if (not $self->greylist()->service()) {
        return;
    }

    $self->setAsChanged();
}


sub mailServicesWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('mailservices', 'Services');
    $widget->add($section);

    my $pop = new EBox::Dashboard::ModuleStatus(
                                                module => 'mail', 
                                                printableName => __('POP3 service'),
                                                running => $self->isRunning('pop'),
                                                service => $self->service('pop'),                                                );
    my $imap = new EBox::Dashboard::ModuleStatus(
                                                 module => 'mail', 
                                                 printableName => __('IMAP service'),
                                                running => $self->isRunning('imap'),
                                                service => $self->service('imap')
                                                                         );
    my $greylist = $self->greylist()->serviceWidget();

    $section->add($pop);
    $section->add($imap);
    $section->add($greylist);

    my $filterSection = $self->_filterDashboardSection();
    $widget->add($filterSection);
}

#
## Method: widgets
#
#       Overriden method that returns summary components
#       for system information
#
sub widgets
{
    return {
        'mail' => {
            'title' => __("Mail"),
            'widget' => \&mailServicesWidget,
            'default' => 1
        }
    };
}

sub _filterDashboardSection
{
    my ($self) = @_;

    my $section = new EBox::Dashboard::Section('mailfilter', 'Mail filter');

    my $service     = $self->service('filter');
    my $statusValue =  $service ? __('enabled') : __('disabled');

    $section->add( new EBox::Dashboard::Value( __('Status'), $statusValue));

    $section->add(
            new EBox::Dashboard::Value(__(q{Mail server's filter}),
                $statusValue)
            );

    $service or return $section;

    my $filter = $self->externalFilter();

    if ($filter eq 'custom') {
        $section->add(new EBox::Dashboard::Value(__('Filter type') =>
            __('Custom')));
        my $address = $self->ipfilter() . ':' . $self->portfilter();
        $section->add(new EBox::Dashboard::Value(__('Address') => $address));
    }else {
        $section->add(
                new EBox::Dashboard::Value(
                    __('Filter type') => $self->_filterAttr($filter,
                        'prettyName')
                    )
                );

        my $global = EBox::Global->getInstance(1);
        my ($filterInstance) =
          grep {$_->mailFilterName eq $filter}
          @{  $global->modInstancesOfType('EBox::Mail::FilterProvider')  };
        $filterInstance->mailFilterDashboard($section);
    }

    return $section;
}

sub menu
{
    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder(
                                        'name' => 'Mail',
                                        'text' => __('Mail')
    );

    $folder->add(
                 new EBox::Menu::Item(
                                      'url' => 'Mail/Composite/General',
                                      'text' => __('General')
                 )
    );

    $folder->add(
                 new EBox::Menu::Item(
                                      'url' => 'Mail/View/VDomains',
                                      'text' => __('Virtual mail domains')
                 )
    );
    $folder->add(
                 new EBox::Menu::Item(
                                      'url' => 'Mail/View/GreylistConfiguration',
                                      'text' => __('Greylist')
                                     ),
                );
    $folder->add(
                 new EBox::Menu::Item(
                                      'url' => 'Mail/QueueManager',
                                      'text' => __('Queue Management')
                 )
    );

    # add filterproviders menu items
    my $global = EBox::Global->getInstance(1);
    my @mods = @{$global->modInstancesOfType('EBox::Mail::FilterProvider')};
    foreach my $mod (@mods) {
        my $menuItem = $mod->mailMenuItem();
        defined $menuItem
          or next;
        $folder->add($menuItem);
    }

    $root->add($folder);
}

sub tableInfo
{
    my $self = shift;
    my $titles = {
                   'postfix_date' => __('Date'),
                   'message_id' => __('Message ID'),
                   'from_address' => __('From'),
                   'to_address' => __('To'),
                   'client_host_name' => __('From hostname'),
                   'client_host_ip' => __('From host ip'),
                   'message_size' => __('Size (bytes)'),
                   'relay' => __('Relay'),
                   'status' => __('Status'),
                   'event' => __('Event'),
                   'message' => __('Aditional Info')
    };
    my @order = (
                 'postfix_date', 'from_address',
                 'to_address', 'client_host_ip',
                 'message_size', 'relay',
                 'status', 'event',
                 'message'
    );

    my $events = {
                   'msgsent' => __('Successful messages'),
                   'maxmsgsize' => __('Maximum message size exceeded'),
                   'maxusrsize' => __('User quote exceeded'),
                   'norelay' => __('Relay access denied'),
                   'noaccount' => __('Account does not exist'),
                   'nohost' => __('Host unreachable'),
                   'noauth' => __('Authentication error'),
                   'other' => __('Other events')
    };

    return {
            'name' => __('Mail'),
            'index' => 'mail',
            'titles' => $titles,
            'order' => \@order,
            'tablename' => 'message',
            'timecol' => 'postfix_date',
            'filter' => ['from_address', 'to_address', 'status'],
            'events' => $events,
            'eventcol' => 'event'
    };
}

sub logHelper
{
    my ($self) = @_;

    return new EBox::MailLogHelper();
}

sub restoreConfig
{
    my ($self, $dir) = @_;

    # recreate maildirs for accounts if needed
    my @vdomains = $self->{vdomains}->vdomains();
    foreach my $vdomain (@vdomains) {
        my @addresses =
          values %{ $self->{musers}->allAccountsFromVDomain($vdomain) };
        foreach my $addr (@addresses) {
            my ($left, $right) = split '@', $addr, 2;
            my $maildir = $self->{musers}->maildir($left, $right);
            if (not -d $maildir) {
                $self->{musers}->_createMaildir($left, $right);
            }
        }
    }

}

# extended backup

sub _storageMailDirs
{
    my @dirs;
    foreach my $dir (qw(/var/mail /var/vmail)) {
        push(@dirs, $dir) if (-d $dir);
    }
    return @dirs;
}

sub _backupMailArchive
{
    my ($self, $dir) = @_;
    return "$dir/mailArchive.tar.bz2";
}

sub extendedBackup
{
    my ($self, %options) = @_;
    my $dir     = $options{dir};

    my @dirsToBackup = $self->_storageMailDirs();

    my $tarFile = $self->_backupMailArchive($dir);

    my $tarCommand =
"/bin/tar -cf $tarFile --bzip2 --atime-preserve --absolute-names --preserve --same-owner @dirsToBackup";
    EBox::Sudo::root($tarCommand);
}

sub extendedRestore
{
    my ($self, %options) = @_;
    my $dir     = $options{dir};

    # erasing actual mail archives
    my @dirsToClean =  $self->_storageMailDirs();
    EBox::info(
"Files in @dirsToClean will be erased and replaced with backup's mail archive"
    );
    EBox::Sudo::root("rm -rf @dirsToClean");

    # restoring backup's mail archives
    my $tarFile = $self->_backupMailArchive($dir);

    if (-e $tarFile) {
        my $tarCommand =
"/bin/tar -xf $tarFile --bzip2 --atime-preserve --absolute-names --preserve --same-owner";
        EBox::Sudo::root($tarCommand);
    }else {
        EBox::error(
"Mail's messages archive not found at $tarFile. Mail's messages will NOT be restored.\n Resuming restoring process.."
          );
    }
}

# Overrides:
#   EBox::Report::DiskUsageProvider::_facilitiesForDiskUsage
sub _facilitiesForDiskUsage
{
    my ($self) = @_;

    my $printableName = __('Mailboxes');

    return {$printableName => [ $self->_storageMailDirs() ],};
}

sub mdQuotaAvailable
{
    my ($self) = @_;

    return (EBox::Config::configkey('mdQuotaAvailable') eq 'yes');
}

sub assureMdQuotaIsAvailable
{
    my ($self) = @_;

    if (not $self->mdQuotaAvailable) {
        throw EBox::Exceptions::Internal('Maildir size quota is not available');
    }
}

# Method: setMDDefaultSize
#
#  This method sets the default maildir size
#
# Parameters:
#
#               size - size of maildir
sub setMDDefaultSize
{
    my ($self, $size)  = @_;

    $self->assureMdQuotaIsAvailable();

    unless (isAPositiveNumber($size)) {
        throw EBox::Exceptions::InvalidData(
                                            'data'      => __('maildir size'),
                                            'value'     => $size
        );
    }



    $self->set_int('mddefaultsize', $size);
}

# Method: getMDDefaultSize
#
#  This method returns the default maildir size
#
sub getMDDefaultSize
{
    my $self = shift;

    $self->assureMdQuotaIsAvailable();

    return $self->get_int('mddefaultsize');
}

1;
