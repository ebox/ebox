DEPENDENCIAS
------------

+ Componentes eBox

	+ ebox

+ Paquetes Debian (apt-get install <paquete>)

	+ openswan

+ Otros

	+ Un n�cleo Linux con IPSec habilitado

INSTALACI�N
-----------

- Cuando todas las dependencias est�n satisfechas, basta con ejecutar:
	
	./configure
	make install

  configure autodetectar� la ruta de eBox base para instalar el m�dulo

- openswan no deber�a ejecutarse autom�ticamente en el arranque, este m�dulo lo
  arrancar� cuando se necesite:

  mv /etc/rcX.d/SXXipsec /etc/rcX.d/KXXipsec

  (reemplazar las X's con los n�meros apropiados)
