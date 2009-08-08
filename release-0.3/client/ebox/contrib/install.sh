#!/bin/sh

install_ebox() {
	cd ebox/trunk
	./autogen.sh --localstatedir=/var
	sudo make install || exit
	sudo cp conf/ebox.conf /etc/apache-perl/conf.d
	sudo /etc/init.d/apache-perl restart
	sudo mkdir /var/ebox/tmp
	sudo mkdir /var/ebox/log
	sudo chown -R www-data.www-data /var/ebox
	sudo cp conf/.gconf.path /var/www
	sudo cp tools/ebox /etc/init.d
	make maintainer-clean
	rmdir config
	rm po/es.po
	svn up po
	cd ../..
}

install_ebox
