## Process this file with automake to produce Makefile.in

perldir = @PERLPATH@/EBox/CGI/Mail

nobase_perl_DATA = CreateAccount.pm CreateAlias.pm DelAccount.pm DelAlias.pm  \
                   SetAccountMaildirQuota.pm \
	CreateGroupAlias.pm DelGroupAlias.pm  \
	 QueueManager.pm MQRemove.pm MQRequeue.pm MQRemoveAll.pm MQFlushAll.pm
MAINTAINERCLEANFILES = Makefile.in

EXTRA_DIST = $(nobase_perl_DATA)
