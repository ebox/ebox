#!/bin/bash -x


INSTALLER=ebox-installer

cp /tmp/$INSTALLER /etc/init.d/$INSTALLER

chmod 0755 /etc/init.d/$INSTALLER

update-rc.d $INSTALLER start  41 S .

# Move eBox packages to where in a Debian system stored
#mv /tmp/*ebox*.deb /var/cache/apt/archives/
#chroot /target apt-get install --download ^ebox.*
chroot /target mount /cdrom
chroot /target apt-cdrom add
chroot /target umount /cdrom

# Set eBox inittab
cp /tmp/inittab /etc/inittab