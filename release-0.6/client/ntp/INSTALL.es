- Antes de instalar este modulo es necesario instalar ebox-base y ntp-server

- Una vez ebox est� instalado:
	
	./configure
	make install

  el script configure autodetecta la instalaci�n de ebox y de ntp-server.

- Actualice el fichero de configuracion de sudo con el comando ebox-sudoers

- Ejecute el script tools/ebox-timezone-import como root.

- No ejecute ntp-server en el arranque, este modulo toma el control de
  ntp-server:

mv /etc/rc2.d/SXXntp-server /etc/rc2.d/KXXntp-server

- Pare ntp-server si est� corriendo.
