DEPENDENCIAS
------------

+ Componentes eBox
	
	+ ebox
	+ ebox-objects
	+ ebox-firewall

+ Paquetes Debian (apt-get install <package>)

	+ squid
	+ dansguardian

INSTALACI�N
-----------

- Una vez ebox est� instalado, ejecuta:
	
	./configure
	make install

  el script configure autodetecta la instalaci�n de ebox.

- No ejecute ni squid ni dansguardian en el arranque, este m�dulo toma el 
  control de ellos.

- Ejecute estas dos l�neas para asegurarse que no se ejecutan los
  demonios al arranque:

mv /etc/rc2.d/SXXsquid /etc/rc2.d/K20squid
mv /etc/rc2.d/SXXdansguardian /etc/rc2.d/K20dansguardian

- Pare squid o dansguardian si est�n ejecut�ndose.

- Cree una tabla de registro escribiendo:

/usr/lib/ebox/ebox-sql-table add access /usr/share/ebox/sqllog/squid.sql

- Reinicie el demonio de log
	
invoke-rc.d ebox logs restart || true

- Instale los servicios de squid y dansguardian

ebox-runit

- Recarge gconf

pkill gconf
