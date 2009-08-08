- Antes de instalar este modulo es necesario instalar ebox-base y squid

- Una vez ebox está instalado:
	
	./configure
	make install

  el script configure autodetecta la instalación de ebox y de squid.

- Actualice el fichero de configuracion de sudo con el comando ebox-sudoers

- No ejecute squid en el arranque, este modulo toma el control de squid:

mv /etc/rc2.d/SXXsquid /etc/rc2.d/K20squid

- Pare squid si está corriendo.
