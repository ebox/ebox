#!/bin/bash -x

. ../build_cd.conf


pushd $CD_BUILD_DIR

apt-ftparchive -c $APTCONF generate $APTCONF_DIR/apt-ftparchive-deb.conf
apt-ftparchive -c $APTCONF generate $APTCONF_DIR/apt-ftparchive-udeb.conf
apt-ftparchive -c $APTCONF generate $APTCONF_DIR/apt-ftparchive-extras.conf
apt-ftparchive -c $APTCONF release $CD_BUILD_DIR/dists/$VERSION > $CD_BUILD_DIR/dists/$VERSION/Release

gpg --default-key $YOURKEYID --output $CD_BUILD_DIR/dists/$VERSION/Release.gpg -ba $CD_BUILD_DIR/dists/$VERSION/Release

rm -f md5sum.txt
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
popd