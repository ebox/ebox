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

3.- Permitir al usuario de apache ejecutar comandos como root con sudo:

    ejecutar "visudo" y añadir esta línea al final del fichero:

    www-data        ALL=NOPASSWD: ALL

4.- Copiar el fichero conf/ebox.conf al directorio conf.d de apache, normalmente
    /etc/apache/conf.d/

5.- Reiniciar apache:

    /etc/init.d/apache restart

6.- Para que ebox se inicie en el arranque de la máquina:

    ln -s /etc/init.d/ebox /etc/rc2.d/S99ebox

7.- Dar permisos de escritura al usuario de apache (www-data) en
    el directorio localstate dir: $prefix/var/lib/ebox o /var/lib/ebox si se ha
    utilizado el argumento --localstatedir=/var/lib/ y crear los directorios tmp
	 y log dentro:

    mkdir /var/lib/ebox/tmp
    mkdir /var/lib/ebox/log
    chown -R www-data.www-data /var/lib/ebox

8.- Si el apache va a escuchar en un puerto distinto al 80, cambiarlo
    usando gconftool o gconf-editor en el directorio gconf
    /ebox/firewall/services.

9.- Copiar conf/.gconf.path al $HOME del usuario que ejecuta apache
	(www-data), normalmente /var/www o /srv/www.

10.- Copiar el script "ebox" a /etc/init.d/ y hacer un enlace en /etc/rc2.d

11.- Eliminar el link a /etc/init.d/apache de /rc2.d/, el script de ebox
     se encargará de arrancar y parar el apache.

EJECUCIÓN
----------

La url del interface de administración es:

http://<ip address>:<apache-port>/ebox/

La contraseña por defecto es 'lala'. Se puede cambiar en la sección general de
configuración.

Los logs de ebox se encuentran en $localstatedir/ebox/log (localstatedir será
$prefix/var por defecto o, si ha usado el parametro aconsejado, /var/lib/).

Algunos errores pueden encontrarse en el log de errores de apache:
/var/log/apache/error.log
