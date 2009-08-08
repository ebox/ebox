DEPENDENCIAS
------------

+ Paquetes debian

# apt-get install <package>

	+ perl
	+ perl-modules
	+ sudo
	+ iproute
	+ iptables
	+ apache
	+ libapache-mod-perl
	+ liblog-dispatch-perl
	+ liblog-log4perl-perl
	+ libhtml-template-perl
	+ liblocale-gettext-perl
	+ libxml-xerces-perl
	+ libxml-simple-perl
	+ libxml-xpath-perl
	+ libnetwork-ipv4addr-perl
	+ liberror-perl
	+ libdevel-stacktrace-perl
	+ libapache-authcookie-perl
	+ gettext

+ modules de cpan

# cpan <module>

	+ HTML::Template::Expr
	+ Locale::TextDomain
	+ Net::Ifconfig::Wrapper
	+ Net::IPv4Addr
	+ Sys::Hostname
	+ Sys::Load
	+ Sys::CPU
	+ Apache::Singleton

Algunos modulos requieren los paquetes gcc, make y libc6-dev para instalarse.


INSTALACIÓN
-----------

1.- Configure:

    Si el apache va a escuchar en un puerto distinto al 80, cambiarlo
    en el fichero de configuración del firewall: conf/firewall.xml.in
    antes de ejecutar configure.

    $ ./configure <arguments>

    Acepta los argumentos estándar de los configure de GNU. Ejecutar
    ./configure --help para obtener una lista.

    Apache se autodetecta.

    Argumento recomendado: --localstatedir=/var , para instalar los datos
    variables en /var, y no en $prefix/var que es lo predeterminado.

2.- Instalación, como root:

    $ make install

3.- Permitir al usuario de apache ejecutar comandos como root con sudo:

    ejecutar "visudo" y añadir esta línea al final del fichero:

    www-data        ALL=NOPASSWD: ALL

4.- Reiniciar apache:

    /etc/init.d/apache restart

5.- Para que ebox se inicie en el arranque de la máquina:

    ln -s /etc/init.d/ebox /etc/rc2.d/S99ebox

6.- Dar permisos de escritura al usuario de apache (www-data) en
    el directorio localstate dir: $prefix/var/ebox o /var/ebox si se ha
    utilizado el argumento --localstatedir=/var

    chown -R www-data.www-data /var/ebox

EJECUCIÓN
----------

La url del interface de administración es:

http://<ip address>:<apache-port>/ebox/

La contraseña por defecto es 'lala'. Se puede cambiar en la sección general de
configuración.

Los logs de ebox se encuentran en $localstatedir/ebox/log (localstatedir será
$prefix/var por defecto o, normalmente, /var)

Algunos errores pueden encontrarse en el log de errores de apache:
/var/log/apache/error.log
