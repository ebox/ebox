#!/bin/sh

mkdir -p config
aclocal -I m4
autoconf
automake --add-missing

cd po
for f in *.po; do
	if test -r "$f"; then
		lang=`echo $f | sed -e 's,\.po$,,'`
		msgfmt -c -o $lang.gmo $lang.po
	fi
done
cd ..

./configure $*
