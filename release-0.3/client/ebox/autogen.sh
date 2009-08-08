#!/bin/sh

mkdir -p config
./tools/po-am.generator > po/Makefile.am
aclocal -I m4
autoconf
automake --add-missing

./configure $*
