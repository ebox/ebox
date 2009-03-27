DEB_CONFIGURE_SCRIPT_ENV += LOGPATH="/var/log/ebox"
DEB_CONFIGURE_SCRIPT_ENV += CONFPATH="/var/lib/ebox/conf"
DEB_CONFIGURE_SCRIPT_ENV += STUBSPATH="/usr/share/ebox/stubs"
DEB_CONFIGURE_SCRIPT_ENV += CGIPATH="/usr/share/ebox/cgi/"
DEB_CONFIGURE_SCRIPT_ENV += TEMPLATESPATH="/usr/share/ebox/templates"
DEB_CONFIGURE_SCRIPT_ENV += SCHEMASPATH="/usr/share/ebox/schemas"
DEB_CONFIGURE_SCRIPT_ENV += WWWPATH="/usr/share/ebox/www/"
DEB_CONFIGURE_SCRIPT_ENV += CSSPATH="/usr/share/ebox/www/css"
DEB_CONFIGURE_SCRIPT_ENV += IMAGESPATH="/usr/share/ebox/www/images"
DEB_CONFIGURE_SCRIPT_ENV += VARPATH="/var"
DEB_CONFIGURE_SCRIPT_ENV += ETCPATH="/etc/ebox"
DEB_CONFIGURE_SCRIPT_ENV += BIND9CONFDIR="/etc/bind" 
DEB_CONFIGURE_SCRIPT_ENV += BIND9CONF="/etc/bind/named.conf" 
DEB_CONFIGURE_SCRIPT_ENV += BIND9CONFOPTIONS="/etc/bind/named.conf.options" 
DEB_CONFIGURE_SCRIPT_ENV += BIND9CONFLOCAL="/etc/bind/named.conf.local" 
DEB_CONFIGURE_SCRIPT_ENV += BIND9_INIT="/etc/init.d/bind9" 

DEB_CONFIGURE_EXTRA_FLAGS := --disable-runtime-tests 
DEB_MAKE_FLAGS += schemadir=usr/share/gconf/schemas
DEB_MAKE_INVOKE = $(MAKE) $(DEB_MAKE_FLAGS) -C $(DEB_BUILDDIR)

$(patsubst %,binary-install/%,$(DEB_PACKAGES)) :: binary-install/%:
	for event in debian/*.upstart ; do \
		[ -f $$event ] || continue; \
		install -d -m 755 debian/$(cdbs_curpkg)/etc/event.d; \
		DESTFILE=$$(basename $$(echo $$event | sed 's/\.upstart//g')); \
		install -m 644 "$$event" debian/$(cdbs_curpkg)/etc/event.d/$$DESTFILE; \
	done;\
	rm -rf debian/$(cdbs_curpkg)/usr/bin \
	rm -rf debian/$(cdbs_curpkg)/usr/sbin
