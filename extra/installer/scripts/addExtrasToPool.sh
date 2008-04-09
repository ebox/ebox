#!/bin/bash


CDIMAGE=/home/javier/installer/cd-image
VERSION=hardy
VERSION_NUMBER=8.04
EXTRAS_SRC=/home/javier/installer/extras


pushd $CDIMAGE

mkdir -p dists/$VERSION/extras/binary-i386 pool/extras/ isolinux preseed

RELEASE_FILE=dists/$VERSION/extras/binary-i386/Release


echo "Archive: $VERSION" > $RELEASE_FILE
echo "Version: $VERSION_NUMBER" >> $RELEASE_FILE
echo Component: extras >> $RELEASE_FILE
echo Origin: Ubuntu >> $RELEASE_FILE
echo Label: Ubuntu >> $RELEASE_FILE
echo Architecture: i386 >> $RELEASE_FILE


rm -rf pool/extras/*
cp -r $EXTRAS_SRC pool/extras


popd