#!/bin/sh

mkdir -p config
aclocal
autoconf
automake --add-missing
./configure $*
