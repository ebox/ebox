# Copyright (C) 2009 eBox Technologies
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

# Class: EBox::WebMail
#
#      Class description
#

package EBox::WebMail;

use strict;
use warnings;

use base qw(EBox::Module::Service
            EBox::Model::ModelProvider
            EBox::Model::CompositeProvider
           );

use EBox::Gettext;
use EBox::Service;
use EBox::Sudo;
use EBox::Config;
use File::Slurp;

use constant {
    MAIN_INC_FILE => '/etc/roundcube/main.inc.php',
    DES_KEY_FILE  => EBox::Config::conf() .  'roundcube.key',

    SIEVE_PLUGIN_INC_FILE => 
           '/usr/share/roundcube/plugins/managesieve/config.inc.php',
};



# Group: Protected methods

# Constructor: _create
#
#        Create an module
#
# Overrides:
#
#        <EBox::Module::Service::_create>
#
# Returns:
#
#        <EBox::WebMail> - the recently created module
#
sub _create
{
        my $class = shift;
        my $self = $class->SUPER::_create(
                                          name => 'webmail',
                                          printableName =>__('Web Mail'),
                                          domain => 'ebox-webmail',
                                         );
        bless($self, $class);
        return $self;
}

# Method: _setConf
#
#        Regenerate the configuration
#
# Overrides:
#
#       <EBox::Module::Service::_setConf>
#
sub _setConf
{
    my ($self) = @_;

    my $params;
    if ($self->_usesEBoxMail()) {
        $params = $self->_confFromMail();
    } else {
        $params = $self->_confForRemoteServer();
    }

    my $managesieve =  $self->_managesieveEnabled();

    my $options = $self->model('Options');
    push @{  $params }, 
        (
         managesieve => $managesieve,
         productName => $options->productName,
         desKey      => $self->desKey(),
        );

    $self->writeConfFile(
                         MAIN_INC_FILE,
                         'webmail/main.inc.php.mas',
                         $params,
                        );

    if ($managesieve) {
        $self->_setManageSievePluginConf();
    }
}


sub _managesieveEnabled
{
    my ($self) = @_;
    if ($self->_usesEBoxMail()) {
        my $mail = EBox::Global->modInstance('mail');
        return $mail->managesieve();
    } else {
        return 
          my $remoteConfRow = $self->model('RemoteServerConfiguration')->row();
        return $remoteConfRow->elementByName('managesieve')->value();
    }
}


sub _setManageSievePluginConf
{
    my ($self) = @_;
    my $params;
    if ($self->_usesEBoxMail()) {
        $params = [
                   host => 'localhost',
                   port => 4190,
                   tls  => 0,
                  ]
    } else {
        $params = 
            $self->model('RemoteServerConfiguration')->getSieveConfiguration();
    }


    $self->writeConfFile(
                         SIEVE_PLUGIN_INC_FILE,
                         'webmail/managesieve-config.php.inc.mas',
                         $params
                        );

}

sub _confFromMail
{
    my ($self) = @_;
    my $mail = EBox::Global->modInstance('mail');
    my @conf;

    if ($mail->imap()) {
        @conf = (
                 imapServer => '127.0.0.1',
                 imapPort   => 143,
                );
    } elsif ($mail->imaps()) {
        @conf = (
                 imapServer => 'ssl://127.0.0.1',
                 imapPort => 993,
                );
    } else {
        throw EBox::Exceptions::External(
__('Neither IMAP nor IMAPS service enabled')
                                        );
    }

    push @conf, (
                 smtpServer => '127.0.0.1',
                 smtpPort   => 25,
                );

    return \@conf;
}

sub _confForRemoteServer
{
    my ($self) = @_;
    return $self->model('RemoteServerConfiguration')->getConfiguration();
}



# Group: Public methods

# Method: menu
#
#       Add an entry to the menu with this module
#
# Overrides:
#
#       <EBox::Module::menu>
#
sub menu
{
    my ($self, $root) = @_;

    my $folder = new EBox::Menu::Folder(
                      'name' => 'WebMail',
                      'text' => $self->printableName(),
                      'separator' => 'Communications',
                      'order' => 700,
    );

    $folder->add(
                 new EBox::Menu::Item(
                        'url' => 'WebMail/Composite/Backend',
                        'text' => __('Backend')
                   )
    );

    $folder->add(
                 new EBox::Menu::Item(
                        'url' => 'WebMail/View/Options',
                        'text' => __('Options')
                   )
        

       );


    $root->add($folder);
}

# Method: modelClasses
#
#       Return the model classes used by the module.
#
# Overrides:
#
#       <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
            'EBox::WebMail::Model::Options',
            'EBox::WebMail::Model::OperationMode',
            'EBox::WebMail::Model::RemoteServerConfiguration',
           ];
}

# Method: compositeClasses
#
#       Return the composite classes used by the module
#
# Overrides:
#
#       <EBox::Model::CompositeProvider::compositeClasses>
#
sub compositeClasses
{
    return [
            'EBox::WebMail::Composite::Backend',
           ];
}

# Method: usedFiles
#
#        Indicate which files are required to overwrite to configure
#        the module to work. Check overriden method for details
#
# Overrides:
#
#        <EBox::Module::Service::usedFiles>
#
sub usedFiles
{
    return [
            {
              'file' => MAIN_INC_FILE,
              'reason' => __('To configure roundcube'),
              'module' => 'webmail'
            },
            {
              'file' => SIEVE_PLUGIN_INC_FILE,
              'reason' => __('To configure managesieve plugin'),
              'module' => 'webmail'
            },
           ];
}

# Method: actions
#
#        Explain the actions the module must make to configure the
#        system. Check overriden method for details
#
# Overrides:
#
#        <EBox::Module::Service::actions>
sub actions
{
    return [
            {
             'action' => __('Create PostgreSQL webmail database'),
             'reason' => __('This database will store the data needed by Roundcube'),
             'module' => 'webmail'
            },
            {
             'action' => __('Add webmail link to www data directory'),
             'reason' => __('Webmail will be accesible at http://ip/webmail'),
             'module' => 'webmail'
            },

           ];
}

# Method: enableActions
#
#        Run those actions explain by <actions> to enable the module
#
# Overrides:
#
#        <EBox::Module::Service::enableActions>
#
sub enableActions
{
    my ($self) = @_;

    if ($self->_usesEBoxMail()) {
        my $mail = EBox::Global->modInstance('mail');
        if ((not $mail->imap())and (not $mail->imaps()) ) {
            throw EBox::Exceptions::External( __x(
q{WebMail module needs IMAP or IMAPS service enabled as long it uses eBox's mail service. You can enable it at {openurl}Mail -> General{closeurl}},
openurl => q{<a href='/ebox/Mail/Composite/General'>},
closeurl => q{</a>}

                                                ) );
        }
    }


    EBox::Sudo::root(EBox::Config::share() . '/ebox-webmail/ebox-webmail-enable');
    $self->_generateDesKeyFile();
}

# Method: disableActions
#
#        Rollback those actions performed by <enableActions> to
#        disable the module
#
# Overrides:
#
#        <EBox::Module::Service::disableActions>
#
sub disableActions
{

}

#  Method: enableModDepends
#
#   Override EBox::Module::Service::enableModDepends
#
sub enableModDepends
{
    my ($self) = @_;
    if ($self->_usesEBoxMail()) {
        return ['mail', 'webserver'];
    }

    return ['webserver'];
}



sub _usesEBoxMail
{
    my ($self) = @_;
    return $self->model('OperationMode')->usesEBoxMail();
}




sub validateIMAPChanges
{
    my ($self, $imap, $imaps) = @_;
    if (not $self->_usesEBoxMail()) {
        return;
    }

    if ($imap or $imaps) {
        $self->setAsChanged();
    } else {
        throw EBox::Exceptions::External( __(
'You cannot disable both IMAP and IMAPS service because they are used by webmail module'
                                            )
                                        );
        
    }

}


sub _generateDesKeyFile
{
    my $desKey = '';
    my $keyLength = 24;
    # length of 24 chars
    my @chars = ('a' .. 'z', 'A' .. 'Z', 0 .. 9, 
                 '(', ')', ',', '#',
                 qw([ ] . : " ! @ $ % ^ & * < > ~ + \ /)
                );
    my $sizeChars = scalar @chars;

    for (1 .. $keyLength) {
        my $i = int(rand($sizeChars));
        $desKey .= $chars[$i];
    }


    EBox::Sudo::root('rm -f ' . DES_KEY_FILE);
    
    EBox::Sudo::command('touch ' . DES_KEY_FILE);
    EBox::Sudo::command('chmod og-rwx ' . DES_KEY_FILE);
    File::Slurp::write_file(DES_KEY_FILE, $desKey);
    
}


sub desKey
{
    my $desKey = File::Slurp::read_file(DES_KEY_FILE);
    return $desKey;
}


1;
