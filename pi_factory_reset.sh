#!/bin/bash
# fail on errors, undefined variables, and errors in pipes
set -eu
set -o pipefail
scripts_dir="$(dirname "${BASH_SOURCE[0]}")"
GIT_DIR="$(realpath $(dirname ${BASH_SOURCE[0]})/..)"
# make sure we're running as the owner of the checkout directory
RUN_AS="$(ls -ld "$scripts_dir" | awk 'NR==1 {print $3}')"
if [ "$USER" != "$RUN_AS" ]
then
    echo "This script must run as $RUN_AS, trying to change user..."
    exec sudo -u $RUN_AS $0
fi
echo ""
read -r -p "Enter the fullname of the image that you want to use (without the img extension): " originalimage
echo ""
MOTD_SHOW_LIVE=""
SET_PI_PASSWORD=""
function main()
{
  pr_header "entering main function"
# paths for base, intermediate and restore images
[ -f ${originalimage}.img ] || { echo "Live image not found '${originalimage}.img'" && exit;  }
IMG_ORIG=${originalimage}.img
IMG_LIVE=${originalimage}.live.img

IMG_RESTORE=${originalimage}.restore.img

IMAGE_FILE_SIZE=$( stat -c %s ${IMG_ORIG} )

echo "Original image size: ${IMAGE_FILE_SIZE}"

echo ""

NEW_FILE_SIZE=$(((( ${IMAGE_FILE_SIZE}*3 ) + ( 512 * 1000 )) / 1024 ))

echo "New image size: ${NEW_FILE_SIZE}K"

# paths to src/dest file that is used for resetting in live image
RECOVERY_SCRIPT_SOURCE="${DIR}/init_resize2.sh"
[ -f ${RECOVERY_SCRIPT_SOURCE} ] || { echo "Not found ${RECOVERY_SCRIPT_SOURCE}" && exit;  }
RECOVERY_SCRIPT_TARGET=/usr/lib/raspi-config/init_resize2.sh
# because of cloning the images, need to generate new UUIDs
UUID_RESTORE=$(uuidgen)
UUID_ROOTFS=$(uuidgen)
# @TODO using the existing UUID_BOOT because it stays the same
# UUID_BOOT=$(tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null  | \
#         dd bs=1 count=8 2>/dev/null)
# partuuid seems to get reset by resize.sh, however UUID doesn't seem to work
set +o pipefail
PARTUUID=$(tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c8)
set -o pipefail
[ ! -z ${PARTUUID} ] || { echo "PARTUUID is empty '${PARTUUID}'" && exit;  }
pr_ok "PARTUUID generated is ${PARTUUID}"
pr_header "2.2 make a copy of the pristine image for use as the live rootfs"
[[ -f "${IMG_LIVE}" ]] && \
{
  pr_warn "live file ${IMG_LIVE} already, exists - overwriting"
  cp -f ${IMG_ORIG} ${IMG_LIVE}
  pr_ok "${IMG_LIVE} created"
} || \
{
  cp -f ${IMG_ORIG} ${IMG_LIVE}
  pr_ok "${IMG_LIVE} created"
}
pr_header "2.3 create an img file for boot, recovery, and rootfs filesystems"
PT_ORIG="$(sfdisk -d ${IMG_ORIG})"
#get the device name for use in the greps
PTABLE_DEVICE=$(echo "${PT_ORIG}" | egrep '^device: ' | cut -d' ' -f2)
#get the existing sector start/sizes
PTABLE_P1_START=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}1" | tr -s ' '| cut -d' ' -f4 | tr -d ',')
PTABLE_P1_SIZE=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}1" | tr -s ' '| cut -d' ' -f6 | tr -d ',')
PTABLE_P2_START=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}2" | tr -s ' '| cut -d' ' -f4 | tr -d ',')
PTABLE_P2_SIZE=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}2" | tr -s ' '| cut -d' ' -f6 | tr -d ',')
# PT_ORIG_P3_START=$(echo "${PT_ORIG}" | egrep "^${PTABLE_DEVICE}2" | tr -s ' '| cut -d' ' -f4 | tr -d ',')
# PTABLE_P3_SIZE=$(echo "${}" | egrep "^${PTABLE_DEVICE}2" | tr -s ' '| cut -d' ' -f6 | tr -d ',')
echo "found boot partition at ${PTABLE_P1_START} with size ${PTABLE_P1_SIZE}"
echo "found root partition at ${PTABLE_P2_START} with size ${PTABLE_P2_SIZE}"
sudo fdisk -l ${IMG_ORIG} | grep 'Sector size'
# # set the size of the new recovery partition in bytes
# ## $(( 2 * 1024**3 )) e.g. 2GiB
# # this should be a multipe of 512 otherwise bad things might happen
# P2_NEWSIZE_BYTES=4294967296
#
# # how many sectors is that?
# P2_SECTORS=$(( ${P2_NEWSIZE_BYTES} / 512 ))
P2_SECTORS=$(( ${PTABLE_P2_SIZE}*2 ))
echo "P2 sectors is ${P2_SECTORS}"
P2_END=$(( PTABLE_P2_START + ${P2_SECTORS} ))
echo "P2_END is ${P2_END}"
# use the sector at the end of P2, find how many bytes that is
# start P3 at the next 8192 boundary after that
PTABLE_P3_START=$(( ((((( P2_END * 512 ) / 8192) + 1) * 8192)/512) ))
# this would need to be much bigger for the desktop/full fat img
[[ -f "${IMG_RESTORE}" ]] && \
{
  pr_warn "restore file ${IMG_RESTORE} already, exists - overwriting"
  dd if=/dev/zero bs=4M count=2000 > ${IMG_RESTORE}
  dd if=/dev/zero bs=1K count=${NEW_FILE_SIZE} > ${IMG_RESTORE}
} || \
{
  dd if=/dev/zero bs=4M count=2000 > ${IMG_RESTORE}
  dd if=/dev/zero bs=1K count=${NEW_FILE_SIZE} > ${IMG_RESTORE}
  # touch ${IMG_RESTORE}
}

pr_header "2.4 Verify that the img file was created"
fdisk -lu ${IMG_RESTORE}
pr_header "2.5 create the filesystem on the img file"
pr_warn "making partition table..."
#${IMG_RESTORE}2 : start=${PTABLE_P2_START}, size=${P2_SECTORS}, type=83
sfdisk ${IMG_RESTORE} <<EOL
label: dos
label-id: 0x${PARTUUID}
unit: sectors
${IMG_RESTORE}1 : start=${PTABLE_P1_START}, size=${PTABLE_P1_SIZE}, type=c
${IMG_RESTORE}2 : start=${PTABLE_P2_START}, size=${P2_SECTORS}, type=83
${IMG_RESTORE}3 : start=${PTABLE_P3_START}, size=${PTABLE_P2_SIZE}, type=83
EOL
pr_header "2.6 Verify that the new filesystem structure"
fdisk -lu ${IMG_RESTORE}
pr_header "2.7 map the img file to loopback device"
LOOP_RESTORE=$(sudo losetup -v  --show -f -P ${IMG_RESTORE})
pr_header "partprobe the new loopback device - ${LOOP_RESTORE}"
sudo partprobe ${LOOP_RESTORE}
pr_header "show the partitions"
losetup -a
##losetup --show -f -P /root/2018-03-13-raspbian-stretch-lite.restore.img
pr_header "3.1 mount the partitions"
#sudo partx --show ${LOOP_RESTORE}
pr_header "find the partitions and add them to loopXpX devices"
#sudo partx -v --add ${LOOP_RESTORE}
pr_header "3.3 map the live img to loopback device"
# losetup -v -f ${IMG_LIVE}
# partx -v --add ${LOOP_RESTORE}
LOOP_LIVE=$(sudo losetup --show -f -P ${IMG_LIVE})
echo "LOOP LIVE is ${LOOP_LIVE}"
sudo partprobe ${LOOP_LIVE}
cat /proc/partitions
sudo losetup -a
sudo blkid
pr_header "3.4 copy the filesystem partitions to the restore img"
sudo dd if=${LOOP_LIVE}p1 of=${LOOP_RESTORE}p1 bs=4M
sudo dd if=${LOOP_LIVE}p2 of=${LOOP_RESTORE}p2 bs=4M
sudo dd if=${LOOP_LIVE}p2 of=${LOOP_RESTORE}p3 bs=4M
# make sure the partitions on the loop device are available
sudo partprobe ${LOOP_RESTORE}
pr_header "3.5 set the UUID_BOOT from the LOOP_LIVE"
#mkdosfs -i ${UUID_BOOT} ${LOOP_RESTORE}p1
UUID_BOOT=$(blkid -o export ${LOOP_LIVE}p1 | egrep '^UUID=' | cut -d'=' -f2)
pr_warn "blkid -o export ${LOOP_RESTORE}p1  is $(blkid -o export ${LOOP_RESTORE}p1 )"
pr_warn "UUID_BOOT is ${UUID_BOOT}"
# fail if we didn't get the boot UUID
[  -z "$UUID_BOOT" ] && \
{
  echo "Empty: Yes"
  exit 99
} || \
{
  echo "Empty: No"
  pr_warn "blkid -o export ${LOOP_RESTORE}p1 is $(blkid -o export ${LOOP_RESTORE}p1 )"
  pr_warn "UUID_BOOT is ${UUID_BOOT}"
}
pr_header "3.6 call tunefs to set label and UUID"
sudo tune2fs ${LOOP_RESTORE}p2 -U ${UUID_RESTORE}
sudo e2label ${LOOP_RESTORE}p2 recoveryfs
sudo tune2fs ${LOOP_RESTORE}p3 -U ${UUID_ROOTFS}
pr_header "3.7 call partprobe"
sudo partprobe ${LOOP_RESTORE}
pr_header "3.8 resize the fs on the recovery partition to fit the restore img"
sudo e2fsck -f ${LOOP_RESTORE}p2
sudo resize2fs ${LOOP_RESTORE}p2
sudo fdisk -lu ${LOOP_RESTORE}
mkdir -p mnt/restore_boot
mkdir -p mnt/restore_recovery
mkdir -p mnt/restore_rootfs
sudo mount ${LOOP_RESTORE}p1 mnt/restore_boot
sudo mount ${LOOP_RESTORE}p2 mnt/restore_recovery
sudo mount ${LOOP_RESTORE}p3 mnt/restore_rootfs
pr_header "4.0 current boot cmdline.txt"
cat mnt/restore_boot/cmdline.txt
pr_header "4.1 create the boot from live rootfs cmdline.txt"
sudo tee mnt/restore_boot/cmdline.txt << EOF
dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=PARTUUID=${PARTUUID}-03 rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait init=/usr/lib/raspi-config/init_resize.sh
EOF
## this not working, as it gets over written
pr_header "4.2 backup original cmdline.txt"
[[ -f mnt/restore_boot/cmdline.txt_original ]] && \
{
  pr_warn "original already  existing, over writing...."
  sudo cp mnt/restore_boot/cmdline.txt mnt/restore_boot/cmdline.txt_original
  pr_ok "copied to original"
} || \
{
  sudo cp mnt/restore_boot/cmdline.txt mnt/restore_boot/cmdline.txt_original
  # ls mnt/restore_boot/cmdline.txt_original
  # cat mnt/restore_boot/cmdline.txt_original
  pr_ok "copied to original"
}
pr_header "4.3 create alt cmd file for recovery boot"
sudo tee mnt/restore_boot/cmdline.txt_recovery << EOF
dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1 root=PARTUUID=XXXYYYXXX rootfstype=ext4 elevator=deadline fsck.repair=yes rootwait init=${RECOVERY_SCRIPT_TARGET}
EOF
## not working;
# init=/boot/factory_reset_restore
#   ___        _               ___         _      _
#  | _ \___ __| |_ ___ _ _ ___/ __| __ _ _(_)_ __| |_
#  |   / -_|_-<  _/ _ \ '_/ -_)__ \/ _| '_| | '_ \  _|
#  |_|_\___/__/\__\___/_| \___|___/\__|_| |_| .__/\__|
#                                           |_|
pr_header "4.4 create factory reset script - run this from live"
sudo tee mnt/restore_boot/factory_reset << EOF
#!/bin/bash
echo "factory restore script"
[[ "\$1" == "--reset" ]] && \
{
  echo "resetting"
  cp -f /boot/cmdline.txt /boot/cmdline.txt_original
  cp -f /boot/cmdline.txt_recovery /boot/cmdline.txt
  sed -i "s/XXXYYYXXX/\$(blkid -o export  \
        /dev/disk/by-uuid/${UUID_RESTORE}  | \
         egrep '^PARTUUID=' | cut -d'=' -f2)/g" /boot/cmdline.txt
  echo "rebooting..."
  reboot
  exit 0
}
EOF
sudo chmod +x mnt/restore_boot/factory_reset
pr_header "4.7 copy init_resize2.sh to recovery"
sudo cp "${RECOVERY_SCRIPT_SOURCE}" "mnt/restore_recovery${RECOVERY_SCRIPT_TARGET}"
sudo chmod +x "mnt/restore_recovery${RECOVERY_SCRIPT_TARGET}"
pr_header "4.8 current boot cmdline.txt"
cat mnt/restore_boot/cmdline.txt
pr_header "4.9 current boot cmdline.txt txt_recovery"
cat mnt/restore_boot/cmdline.txt_recovery
pr_header "4.9.1 enable ssh on the image"
sudo touch mnt/restore_boot/ssh
pr_header "4.10 current recovery fstab"
cat mnt/restore_recovery/etc/fstab
pr_header "4.11 indicate this is a recovery shell"
sudo tee mnt/restore_recovery/etc/motd << EOF
##    ____  _____ ____ _____     _______ ______   __
##   |  _ \| ____/ ___/ _ \ \   / / ____|  _ \ \ / /
##   | |_) |  _|| |  | | | \ \ / /|  _| | |_) \ V /
##   |  _ <| |__| |__| |_| |\ V / | |___|  _ < | |
##   |_| \_\_____\____\___/  \_/  |_____|_| \_\|_|
##
EOF
pr_header "map the recovery fstab to the 2nd partition"
sudo tee mnt/restore_recovery/etc/fstab << EOF
proc                    /proc  proc    defaults          0       0
UUID=${UUID_BOOT}       /boot  vfat    defaults          0       2
UUID=${UUID_RESTORE}    /      ext4    defaults,noatime  0       1
EOF
pr_header "indicate this it is the live shell"
[  -z "$MOTD_SHOW_LIVE" ] && \
{
  echo "not editing live message"
} || \
{
sudo tee mnt/restore_rootfs/etc/motd << EOF
##    _     _____     _______
##   | |   |_ _\ \   / / ____|
##   | |    | | \ \ / /|  _|
##   | |___ | |  \ V / | |___
##   |_____|___|  \_/  |_____|
##
EOF
}
  pr_header "current live fstab"
  cat mnt/restore_rootfs/etc/fstab
  pr_header "map the live fstab to the 3rd partition"
sudo tee mnt/restore_rootfs/etc/fstab << EOF
proc                     /proc  proc    defaults          0       0
UUID=${UUID_BOOT}  /boot  vfat    defaults          0       2
UUID=${UUID_ROOTFS}  /      ext4    defaults,noatime  0       1
EOF
pr_header "change the pi user password"
[  -z "$SET_PI_PASSWORD" ] && \
{
  echo "Not setting pi password"
} || \
{
  newsalt=$(pwgen -s 12 1)
  # @TODO add parameter for password setting
  newpass_raw="xxx"
  newpass_cmd="perl -e 'print crypt(\"${newpass_raw}\",\"\\\$6\\\$${newsalt}\\$\") . \"\n\"'"
  echo "newpass_cmd is ${newpass_cmd}"
  newpass=$(eval ${newpass_cmd})
# perl -pe 's|(root):(\$.*?:)|\1:\$6\$SALTsalt\$UiZikbV3VeeBPsg8./Q5DAfq9aj7CVZMDU6ffBiBLgUEpxv7LMXKbcZ9JSZnYDrZQftdG319XkbLVMvWcF/Vr/:|' /etc/shadow > /etc/shadow.new
#sudo sed "s/^pi:\(.*\):\(.*\):\(.*\):\(.*\):\(.*\):\(.*\):\(.*\)/pi:${newpass}:\2:\3:\4:\5:\6:\7/" mnt/restore_rootfs/etc/shadow
  pr_alert "insert the pi user password"
  sudo awk -v var="${newpass}" \
      -F: 'BEGIN{OFS=":";} $1=="pi"{$2=var}1' \
      mnt/restore_rootfs/etc/shadow \
      > shadow.1 \
      && sudo cp -f shadow.1 mnt/restore_rootfs/etc/shadow
  sudo chown 0:42   mnt/restore_rootfs/etc/shadow
  sudo chmod 640   mnt/restore_rootfs/etc/shadow
  sudo awk -v var="${newpass}" \
      -F: 'BEGIN{OFS=":";} $1=="pi"{$2=var}1' \
      mnt/restore_recovery/etc/shadow \
      > shadow.2 \
      && sudo cp -f shadow.2 mnt/restore_recovery/etc/shadow
  sudo chown 0:42   mnt/restore_recovery/etc/shadow
  sudo chmod 640   mnt/restore_recovery/etc/shadow
}
# perl -pe 's|(root):(\$.*?:)|\1:\$6\$SALTsalt\$UiZikbV3VeeBPsg8./Q5DAfq9aj7CVZMDU6ffBiBLgUEpxv7LMXKbcZ9JSZnYDrZQftdG319XkbLVMvWcF/Vr/:|' \
# /etc/shadow > /etc/shadow.new
# python -c "import crypt, getpass, pwd; \
#          print crypt.crypt('password', '\$6\$SALTsalt\$')"
  pr_header "copy the recovery image to the recovery /opt dir for restoring"
  # dd if=${LOOP_RESTORE}p3 of=mnt/restore_recovery/opt/recovery.img bs=4M
  sudo dd bs=4M if=${LOOP_RESTORE}p3 | sudo zip mnt/restore_recovery/opt/recovery.img.zip -
  pr_header "recovery image..."
  pr_ok "recovery image is ${IMG_RESTORE}"
}
function cleanup()
{
  pr_header "don't need partitions anymore unmount"
  sudo umount -f -d mnt/restore_boot || true
  sudo umount -f -d mnt/restore_rootfs || true
  sudo umount -f -d mnt/restore_recovery || true
  pr_header "detach loop devices"
  sudo losetup --detach-all
}
# get current source dir, even if its hidden in links
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
source "${DIR}/display_funcs.sh"
# if the script failed, cleanup previous run.
# cleanup
main
cleanup