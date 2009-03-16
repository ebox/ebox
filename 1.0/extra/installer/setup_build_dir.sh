#!/bin/bash

. ./build_cd.conf

ISO=$1
if [ -z $ISO ]; then
    echo "You must specify the Ubuntu server ISO image as first parameter"
    exit 1
fi

MOUNTDIR=/tmp/tmpmount || exit 1

mkdir -p $MOUNTDIR || exit 1
sudo mount -o loop $ISO $MOUNTDIR || exit 1

rm -rf $CD_BUILD_DIR || exit 1
cp -r $MOUNTDIR $CD_BUILD_DIR || exit 1
chmod a+w -R $CD_BUILD_DIR || exit 1

# Rebranding
cp images/* $CD_BUILD_DIR/isolinux/
sed -i 's/GFXBOOT bootlogo/GFXBOOT bootlogo\nGFXBOOT-FOREGROUND 0x000000/g' $CD_BUILD_DIR/isolinux/isolinux.cfg
sed -i 's/Ubuntu Server/eBox Platform 1.0/g' $CD_BUILD_DIR/isolinux/isolinux.cfg

sudo umount $MOUNTDIR || exit 1
rmdir $MOUNTDIR

echo "CD Installer build directory generated from contents of $ISO"
