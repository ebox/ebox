## Process this file with automake to produce Makefile.in

Stubdir = @STUBSPATH@/mail



nobase_Stub_DATA = main.cf.mas master.cf.mas \
                   sasl_passwd.mas \
                   ebox.postgrey.mas whitelist_clients.mas \
                   dovecot.conf.mas dovecot-ldap.conf.mas \
	           archivemail.mas \
		   helo_checks.pcre.mas \
		   fetchmail.rc.mas fetchmail-update.cron.mas


EXTRA_DIST = $(nobase_Stub_DATA)

MAINTAINERCLEANFILES = Makefile.in
