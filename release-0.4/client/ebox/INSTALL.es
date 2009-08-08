DEPENDENCIAS
------------

+ Paquetes debian

# apt-get install <package>

	+ perl
	+ perl-modules
	+ sudo
	+ iproute
	+ iptables
	+ apache-perl
	+ dhcp3-client
	+ libapache-mod-perl
	+ liblog-dispatch-perl
	+ liblog-log4perl-perl
	+ liblocale-gettext-perl
	+ libnetwork-ipv4addr-perl
	+ liberror-perl
	+ libdevel-stacktrace-perl
	+ libapache-authcookie-perl
	+ libgnome2-gconf-perl
	+ libnet-ifconfig-wrapper-perl
	+ libsys-cpu-perl
	+ libsys-cpuload-perl
	+ libnetwork-ipv4addr-perl
	+ gettext

+ modulos de cpan

	ninguno en este momento

INSTALACIÓN
-----------

1.- Configure:

    $ ./configure <arguments>

    Acepta los argumentos estándar de los configure de GNU. Ejecutar
    ./configure --help para obtener una lista.

    Apache se autodetecta.

    Argumento recomendado: --localstatedir=/var/lib/ , para instalar los datos
    variables en /var/lib/, y no en $prefix/var/lib/ que es lo predeterminado.

2.- Instalación, como root:

    $ make install

3.- Permitir al usuario de ebox (configurado en $sysconfdir/ebox/ebox.conf)
    ejecutar comandos como root con sudo. Para ello incluir la salida del
    comando ebox-sudoers en el fichero /etc/sudoers. Si el usuario de ebox va a
    ser el único que necesite usar sudo se puede simplemente sobreescribir el
    /etc/sudoers con la salida de ebox-sudoers:

    ebox-sudoers > /etc/sudoers

4.- Para que ebox se inicie en el arranque de la máquina:

    cp tools/ebox /etc/init.d
    ln -s /etc/init.d/ebox /etc/rc2.d/S99ebox

5.- Dar permisos de escritura al usuario de ebox en
    el directorio localstate dir: $prefix/var/ebox o /var/ebox si se ha
    utilizado el argumento --localstatedir=/var/ y crear los directorios tmp
	 y log dentro:

    mkdir /var/ebox/tmp
    mkdir /var/ebox/log
    chown -R ebox.ebox /var/ebox

7.- Copiar conf/.gconf.path al $HOME del usuario de ebox

8.- Eliminar el link a /etc/init.d/apache de /rc2.d/, el script de ebox
    se encargará de arrancar y parar el apache.

8.- Arrancar ebox:
	
	/etc/init.d/ebox start

EJECUCIÓN
----------

La url del interface de administración es (el puerto por defecto es el 80):

http://<ip address>

La contraseña por defecto es 'lala'. Se puede cambiar en la sección general de
configuración.

Los logs de ebox y de apache se encuentran en $localstatedir/ebox/log
