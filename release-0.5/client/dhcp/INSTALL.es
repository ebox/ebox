- Antes de instalar este modulo es necesario instalar ebox-base y dhcp3-server.

- Una vez ebox está instalado:
	
	./configure
	make install

  el script configure autodetecta la instalación de ebox.

- Actualice el fichero de configuracion de sudo con el comando ebox-sudoers

- No ejecute dhcp3-server en el arranque, este modulo toma el control de él:

mv /etc/rc2.d/SXXdhcp3-server /etc/rc2.d/K20dhcp3-server

- Pare dhcp3-server si está corriendo.
