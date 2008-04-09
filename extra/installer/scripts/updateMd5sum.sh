#!/bin/bash -x
BUILD=/home/javier/installer/cd-image
APTCONF=/home/javier/installer/apt-ftparchive/release.conf
DISTNAME=hardy
YOURKEYID=25AFCD6C

pushd $BUILD
apt-ftparchive -c $APTCONF generate /home/javier/installer/apt-ftparchive/apt-ftparchive-deb.conf
apt-ftparchive -c $APTCONF generate /home/javier/installer/apt-ftparchive/apt-ftparchive-udeb.conf
apt-ftparchive -c $APTCONF generate /home/javier/installer/apt-ftparchive/apt-ftparchive-extras.conf
apt-ftparchive -c $APTCONF release $BUILD/dists/$DISTNAME > $BUILD/dists/$DISTNAME/Release

gpg --default-key $YOURKEYID --output $BUILD/dists/$DISTNAME/Release.gpg -ba $BUILD/dists/$DISTNAME/Release
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
popd