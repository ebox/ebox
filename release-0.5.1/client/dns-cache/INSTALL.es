- Antes de instalar este modulo es necesario instalar ebox-base y bind9

- Una vez ebox está instalado:
	
	./configure
	make install

  el script configure autodetecta la instalación de ebox y de bind9.

- Actualice el fichero de configuracion de sudo con el comando ebox-sudoers

- No ejecute bind9 en el arranque, este modulo toma el control de bind9:

mv /etc/rc2.d/SXXbind9 /etc/rc2.d/KXXbind9

- Pare bind9 si está corriendo.
