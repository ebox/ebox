DEPENDENCIAS
------------

+ Componentes eBox

	+ ebox
	+ ebox-firewall

+ Paquetes Debian (apt-get install <paquete>)
	
	+ ntpdate 
	+ ntp-server

INSTALACI�N
-----------

- Una vez ebox est� instalado:
	
	./configure --prefix=/usr --localstatedir=/var --sysconfdir=/etc
	make install

  el script configure autodetecta la instalaci�n de ebox y de ntp-server.

- Ejecute el script /usr/lib/ebox-ntp/ebox-timezone-import con
  permisos de administrador.

- No ejecute ntp-server en el arranque, este m�dulo toma el control de
  ntp-server usando runit:

mv /etc/rc2.d/SXXntp-server /etc/rc2.d/KXXntp-server
ebox-runit

- Pare ntp-server si est� corriendo.
