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
	+ dhcp3-client
	+ libapache-mod-perl
	+ liblog-dispatch-perl
	+ liblog-log4perl-perl
	+ libhtml-template-perl
	+ libhtml-template-expr-perl
	+ liblocale-gettext-perl
	+ libnetwork-ipv4addr-perl
	+ liberror-perl
	+ libdevel-stacktrace-perl
	+ libapache-authcookie-perl
	+ libgnome2-gconf-perl
	+ libnet-ifconfig-wrapper-perl
	+ libsys-cpu-perl
	+ libsys-cpuload-perl
	+ libintl-perl
	+ libnetwork-ipv4addr-perl
	+ gettext

+ modulos de cpan

# cpan <module>

No se necesita ning�n modulo de cpan en estos momentos.

INSTALACI�N
-----------

1.- Configure:

    $ ./configure <arguments>

    Acepta los argumentos est�ndar de los configure de GNU. Ejecutar
    ./configure --help para obtener una lista.

    Apache se autodetecta.

    Argumento recomendado: --localstatedir=/var , para instalar los datos
    variables en /var, y no en $prefix/var que es lo predeterminado.

2.- Instalaci�n, como root:

    $ make install

3.- Permitir al usuario de apache ejecutar comandos como root con sudo:

    ejecutar "visudo" y a�adir esta l�nea al final del fichero:

    www-data        ALL=NOPASSWD: ALL

4.- Reiniciar apache:

    /etc/init.d/apache restart

5.- Para que ebox se inicie en el arranque de la m�quina:

    ln -s /etc/init.d/ebox /etc/rc2.d/S99ebox

6.- Dar permisos de escritura al usuario de apache (www-data) en
    el directorio localstate dir: $prefix/var/ebox o /var/ebox si se ha
    utilizado el argumento --localstatedir=/var

    chown -R www-data.www-data /var/ebox

7.- Si el apache va a escuchar en un puerto distinto al 80, cambiarlo
    usando gconftool o gconf-editor en el directorio gconf
    /ebox/firewall/services.


EJECUCI�N
----------

La url del interface de administraci�n es:

http://<ip address>:<apache-port>/ebox/

La contrase�a por defecto es 'lala'. Se puede cambiar en la secci�n general de
configuraci�n.

Los logs de ebox se encuentran en $localstatedir/ebox/log (localstatedir ser�
$prefix/var por defecto o, normalmente, /var)

Algunos errores pueden encontrarse en el log de errores de apache:
/var/log/apache/error.log
