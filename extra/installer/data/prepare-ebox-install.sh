#!/bin/bash -x

INSTALLER=ebox-installer

cp /tmp/$INSTALLER /etc/init.d/$INSTALLER
chmod 0755 /etc/init.d/$INSTALLER
update-rc.d $INSTALLER start  41 S .

# Set eBox inittab
cp /tmp/inittab /etc/inittab
cp /tmp/locale.gen /var/tmp