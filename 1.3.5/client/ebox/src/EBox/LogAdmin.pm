# Copyright (C) 2006 Warp Networks S.L.
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

package EBox::LogAdmin;

use strict;
use warnings;

use Error qw(:try);

use EBox::Global;
use EBox::Gettext;
use EBox::Config;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::External;
use EBox::DBEngineFactory;

use Apache2::RequestUtil;
use Apache2::Connection;



BEGIN {
	use Exporter ();
	our($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	@ISA = qw(Exporter);
	@EXPORT = qw();
	%EXPORT_TAGS = (all => [qw{ logAdminNow logAdminDeferred
	               commitPending rollbackPending pendingActions } ], );
	@EXPORT_OK = qw();
	Exporter::export_ok_tags('all');
	$VERSION = EBox::Config::version;
}

# Method: logAdmin
#
#	This function logs an administrative action
#
#
sub _logAdmin
{
	my ($module, $action, $params, $committed) = @_;

	my $source = _actionSource();

	my $dbengine = EBox::DBEngineFactory::DBEngine();

	my $time = localtime();
	my $data = { 'timestamp' => $time, 'source' => $source,
		'module' => $module, 'action' => $action, 'params' => $params, 'committed' => $committed };
	$dbengine->insert('admin', $data);
}


sub _actionSource
{
  my $req;
  try {
    $req = Apache2::RequestUtil->request();
  }
  otherwise {
    # if  Apache2::RequestUtil->request() fails we aren't running inside apache
    # so we will assume that we are calling ebox API from a script or similiar
    $req = undef;
  };


  if (defined $req) {
    return $req->connection->remote_host();
  }
  else {
    return 'local';
  }

}

# Method: logAdminDeferred
sub logAdminDeferred
{
	my ($module, $action, $params) = @_;
	_logAdmin($module, $action, $params, 'false');
}

# Method: logAdminNow
sub logAdminNow
{
	my ($module, $action, $params) = @_;
	_logAdmin($module, $action, $params, 'true');
}

# Method: commitPending
sub commitPending
{
	my $dbengine = EBox::DBEngineFactory::DBEngine();
	$dbengine->query("UPDATE admin SET committed = 'true' WHERE committed = 'f'");
}

# Method: rollbackPending
sub rollbackPending
{
	my $dbengine = EBox::DBEngineFactory::DBEngine();
	$dbengine->query("DELETE FROM admin WHERE committed = 'f'");
}

# Method: pendingActions
sub pendingActions
{
	my $dbengine = EBox::DBEngineFactory::DBEngine();
	my $ret = $dbengine->query("SELECT * FROM admin WHERE committed = 'false' ORDER BY timestamp, module");

	my $global = EBox::Global->getInstance(1);

	# group the actions by module and add the title of the module
	my $actions = [];
	foreach my $action (@{$ret}) {
		my $modname = $action->{'module'};
		if($global->modExists($modname)) {
			my $mod = EBox::Global->modInstance($modname);
			my $domain = settextdomain($mod->domain);
			$action->{'modtitle'} = __d($mod->title(), $mod->domain());
			#TODO: create a function out of these lines and put it
			#somewhere where it can be used from here and as a
			#filter for logviewer for the admin table
			my $action = $action->{'action'};
			my @params = split(',', $action->{'params'});
			@params = map {
				my @field = split("=",$_);
				defined($field[1]) or $field[1] = '';
				$field[0] => $field[1];
			} @params;
			$action->{'message'} = __x($mod->actionMessage($action),@params);
			settextdomain($domain);
		} else {
			$action->{'modtitle'} = $modname;
		}
		push(@{$actions}, $action);
	}
	return $actions;
}

1;
