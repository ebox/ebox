- Para instalar este m�dulo es necesario instalar eBox base, openswan y un
  kernel linux con soporte para IPSec.

- Cuando se todas las dependencias est�n satisfechas, basta con ejecutar:
	
	./configure
	make install

  configure autodetectar� la ruta de eBox base para instalar el m�dulo

- Actualiza el fichero sudoers con el comando ebox-sudoers.

- openswan no deber�a ejecutarse autom�ticamente en el arranque, este m�dulo lo
  arrancar� cuando se necesite:

  mv /etc/rcX.d/SXXipsec /etc/rcX.d/KXXipsec

  (reemplazar las X's con los n�meros apropiados)
