#!/bin/bash

PATCH=$(cat /patch)

# This script will be run in chroot under qemu.

echo "[INFO] Initializing.."
. init.sh

echo "[INFO] Creating \"fstab\""
echo "# hemx8mmini fstab" > /etc/fstab
echo "" >> /etc/fstab
echo "proc            /proc           proc    defaults        0       0
UUID=${UUID_BOOT} /boot           vfat    defaults,utf8,user,rw,umask=111,dmask=000        0       1
tmpfs   /var/log                tmpfs   size=20M,nodev,uid=1000,mode=0777,gid=4, 0 0
tmpfs   /var/spool/cups         tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /var/spool/cups/tmp     tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /tmp                    tmpfs   defaults,noatime,mode=0755 0 0
tmpfs   /dev/shm                tmpfs   defaults,nosuid,noexec,nodev        0 0
" > /etc/fstab

echo "[INFO] Modifying uEnv.txt template"
sed -i "s/%%BOOTPART%%/${UUID_BOOT}/g" /boot/uEnv.txt
sed -i "s/%%IMGPART%%/${UUID_IMG}/g" /boot/uEnv.txt
sed -i "s/%%DATAPART%%/${UUID_DATA}/g" /boot/uEnv.txt

echo "[INFO] Fixing armv8 deprecated instruction emulation with armv7 rootfs"
echo "abi.cp15_barrier=2" >> /etc/sysctl.conf

echo "[INFO] Alsa Card Ordering"
echo "# USB DACs will have device number 5 in whole Volumio device range
options snd-usb-audio index=5" >> /etc/modprobe.d/alsa-base.conf

echo "[INFO] Installing additional packages"
apt-get update
apt-get -y install device-tree-compiler u-boot-tools bluez-firmware  

echo "[INFO] Enabling hemx8mmini Bluetooth stack"
ln -sf /lib/firmware /etc/firmware
ln -s /lib/systemd/system/variscite-bt.service /etc/systemd/system/multi-user.target.wants/variscite-bt.service

echo "[INFO] Enabling hemx8mmini wireless stack"
ln -s /lib/systemd/system/variscite-wifi.service /etc/systemd/system/multi-user.target.wants/variscite-wifi.service

echo "[INFO] Adding custom modules overlayfs, squashfs and nls_cp437"
echo "overlay" >> /etc/initramfs-tools/modules
echo "squashfs" >> /etc/initramfs-tools/modules
echo "nls_cp437" >> /etc/initramfs-tools/modules

echo "[INFO] Copying volumio initramfs updater"
cd /root/
mv volumio-init-updater /usr/local/sbin

echo "[INFO] Removing unused features"
rm /etc/xbindkeysrc
rm /etc/systemd/system/multi-user.target.wants/xbindkeysrc.service

#On The Fly Patch
if [ "$PATCH" = "volumio" ]; then
echo "[INFO] No Patch To Apply"
else
echo "[INFO] Applying Patch ${PATCH}"
PATCHPATH=/${PATCH}
cd $PATCHPATH
#Check the existence of patch script
if [ -f "patch.sh" ]; then
sh patch.sh
else
echo "[INFO] Cannot Find Patch File, aborting"
fi
if [ -f "install.sh" ]; then
sh install.sh
fi
cd /
rm -rf ${PATCH}
fi
rm /patch

echo "[INFO] mkinitramfs: changing to 'modules=list'"
sed -i "s/MODULES=most/MODULES=list/g" /etc/initramfs-tools/initramfs.conf

echo "[INFO] Installing winbind here, since it freezes networking"
apt-get update
apt-get install -y winbind libnss-winbind

echo "[INFO] Cleaning APT Cache and remove policy file"
rm -f /var/lib/apt/lists/*archive*
apt-get clean
rm /usr/sbin/policy-rc.d

#First Boot operations
echo "[INFO] Signalling the init script to re-size the volumio data partition"
touch /boot/resize-volumio-datapart

echo "Creating initramfs 'volumio.initrd'"
mkinitramfs-custom.sh -o /tmp/initramfs-tmp

echo "Creating uInitrd from 'volumio.initrd'"
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n uInitrd -d /boot/volumio.initrd /boot/uInitrd

echo "Removing unnecessary /boot files"
rm /boot/volumio.initrd
