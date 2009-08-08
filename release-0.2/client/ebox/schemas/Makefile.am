## Process this file with automake to produce Makefile.in

schemadir   = @GCONF_SCHEMA_FILE_DIR@
schema_DATA = firewall.schemas global.schemas network.schemas objects.schemas \
		sysinfo.schemas

EXTRA_DIST = $(schema_DATA)

MAINTAINERCLEANFILES = Makefile.in

install-data-local:
	GCONF_CONFIG_SOURCE=$(GCONF_SCHEMA_CONFIG_SOURCE) $(GCONFTOOL) \
		--makefile-install-rule $(srcdir)/$(schema_DATA)
