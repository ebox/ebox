- Antes de instalar este modulo es necesario instalar ebox-base y dhcp3-server.

- Una vez ebox est� instalado:
	
	./configure
	make install

  el script configure autodetecta la instalaci�n de ebox.

- Actualice el fichero de configuracion de sudo con el comando ebox-sudoers

- No ejecute dhcp3-server en el arranque, este modulo toma el control de �l:

mv /etc/rc2.d/SXXdhcp3-server /etc/rc2.d/K20dhcp3-server

- Pare dhcp3-server si est� corriendo.
