- Antes de instalar este modulo es necesario instalar ebox-base

- Una vez ebox est� instalado:
	
	./configure
	make install

  el script configure autodetecta la instalaci�n de ebox y de squid.

- Asegurese de que el usuario de apache puede escribir en /etc/squid/squid.conf

- No ejecute squid en el arranque, este modulo toma el control de squid:

mv /etc/rc2.d/SXXsquid /etc/rc2.d/K20squid

- Pare squid si est� corriendo.

- Aseg�rese de que el directorio localstatedir de ebox puede se escrito por el
  usuario de apache (hay ficheros nuevos ahora en este directorio):

  chown -R www-data.www-data $localstatedir/ebox/
