#!/bin/bash -x

CDIMAGE=/home/javier/installer/cd-image
SRCDIR=/home/javier/installer
EBOXDIR=$CDIMAGE/ebox

test -d $CDIMAGE || (echo "Inexistent CD image dir: $CDIMAGE" && exit 1)
test -d $SRCDIR  || (echo "Inexistent source dir: $SRCDIR" && exit 1)
test -d $DEBDIR  || (echo "Inexistent extra debs dir: $DEBDIR" && exit 1)


cp $SRCDIR/ubuntu-ebox.seed $CDIMAGE/preseed/ubuntu-server.seed


test -d $EBOXDIR || mkdir -p $EBOXDIR

rm -rf $EBOXDIR/*

cp $SRCDIR/ebox-installer $SRCDIR/prepare-ebox-install.sh $EBOXDIR/
cp $SRCDIR/inittab $SRCDIR/locale.gen $EBOXDIR/
