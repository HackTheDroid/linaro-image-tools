#!/bin/bash -e

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

MIRROR="http://rcn-ee.net/deb/tools/"
MLO="MLO-beagleboard-1.44+r10+gitr1c9276af4d6a5b7014a7630a1abeddf3b3177563-r10"
XLOAD="x-load-beagleboard-1.44+r10+gitr1c9276af4d6a5b7014a7630a1abeddf3b3177563-r10.bin.ift"
UBOOT="u-boot-beagleboard-2010.03-rc1+r45+gitr946351081bd14e8bf5816fc38b82e004a0e6b4fe-r45.bin"

unset UBOOT_FILE
unset XLOADER_FILE
unset MLO_FILE

unset MMC

#Defaults
RFS=ext3
BOOT_LABEL=boot
RFS_LABEL=rootfs

DIR=$PWD

function prepare_sources {
 if [ "$CHESSY_SOURCE" ] ; then
  rm -rf ${DIR}/boot/ || true
  tar xf binary-boot.omap.tar.gz 
  ln -sf boot/initrd.img-* .
  ln -sf boot/vmlinuz-* .
  if [ ! -f boot.cmd ] ; then
    cat > boot.cmd << BOOTCMD
setenv bootcmd 'mmc init; fatload mmc 0:1 0x80000000 uImage; fatload mmc 0:1 0x81600000 uInitrd; bootm 0x80000000 0x81600000'
setenv bootargs 'console=tty0 console=ttyS2,115200n8 earlyprintk root=/dev/mmcblk0p2 rootwait ro vram=12M omapfb.debug=y omapfb.mode=dvi:1280x720MR-16@60'
boot
BOOTCMD
  fi
 fi
}


function dl_xload_uboot {
 echo ""
 echo "Downloading X-loader and Uboot if required"
 echo ""

 if [ "$MLO_FILE" ]; then
  echo ""
  echo "Using MLO file $MLO_FILE"
  echo ""
 else
  wget -c --no-verbose --directory-prefix=${DIR}/deploy/ ${MIRROR}${MLO}
  MLO_FILE="${DIR}/deploy/{$MLO}"
 fi

 if [ "$XLOADER_FILE" ]; then
  echo ""
  echo "Using xloader file $XLOADER_FILE"
  echo ""
 else
  wget -c --no-verbose --directory-prefix=${DIR}/deploy/ ${MIRROR}${XLOAD}
  XLOADER_FILE="${DIR}/deploy/{$XLOAD}"
 fi

 if [ -n "$UBOOT_FILE" ]; then
  echo ""
  echo "Using uboot file $UBOOT_FILE"
  echo ""
 else
   wget -c --no-verbose --directory-prefix=${DIR}/deploy/ ${MIRROR}${UBOOT}
   UBOOT_FILE="${DIR}/deploy/$UBOOT"
 fi
}

function cleanup_sd {

 echo ""
 echo "Umounting Partitions"
 echo ""

 sudo umount ${MMC}1 &> /dev/null || true
 sudo umount ${MMC}2 &> /dev/null || true

 sudo parted -s ${MMC} mklabel msdos
}

function create_partitions {

sudo fdisk -H 255 -S 63 ${MMC} << END
n
p
1
1
+64M
a
1
t
e
p
w
END

echo ""
echo "Formating Boot Partition"
echo ""

sudo mkfs.vfat -F 16 ${MMC}1 -n ${BOOT_LABEL}

sudo rm -rfd ${DIR}/disk || true

mkdir ${DIR}/disk
sudo mount ${MMC}1 ${DIR}/disk

sudo cp -v ${MLO_FILE} ${DIR}/disk/MLO
# sudo cp -v ${XLOADER_FILE} ${DIR}/disk/x-load.bin.ift
sudo cp -v ${UBOOT_FILE} ${DIR}/disk/u-boot.bin

cd ${DIR}/disk
sync
cd ${DIR}
sudo umount ${DIR}/disk || true
echo "done"

sudo fdisk ${MMC} << ROOTFS
n
p
2


p
w
ROOTFS

echo ""
echo "Formating ${RFS} Partition"
echo ""
sudo mkfs.${RFS} ${MMC}2 -L ${RFS_LABEL}

}

function populate_boot {
 echo ""
 echo "Populating Boot Partition"
 echo ""
 sudo mount ${MMC}1 ${DIR}/disk
 sudo mkimage -A arm -O linux -T kernel -C none -a 0x80008000 -e 0x80008000 -n "Linux" -d ${DIR}/vmlinuz-* ${DIR}/disk/uImage
 sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d ${DIR}/initrd.img-* ${DIR}/disk/uInitrd

 sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Ubuntu 10.04" -d ${DIR}/boot.cmd ${DIR}/disk/boot.scr
 #for igepv2 users
 sudo cp -v ${DIR}/disk/boot.scr ${DIR}/disk/boot.ini

 echo "#!/bin/sh" > /tmp/rebuild_uinitrd.sh
 echo "" >> /tmp/rebuild_uinitrd.sh
 echo "DIR=\$PWD" >> /tmp/rebuild_uinitrd.sh
 echo "sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) \${DIR}/uInitrd" >> /tmp/rebuild_uinitrd.sh
 echo "" >> /tmp/rebuild_uinitrd.sh

 sudo cp -v /tmp/rebuild_uinitrd.sh ${DIR}/disk/rebuild_uinitrd.sh
 sudo chmod +x ${DIR}/disk/rebuild_uinitrd.sh

 cd ${DIR}/disk/
 sync
 sync
 cd ${DIR}/

 sudo umount ${DIR}/disk || true
}

function populate_rootfs {
 echo ""
 echo "Populating rootfs Partition"
 echo "Be patient, this may take a few minutes"
 echo ""
 sudo mount ${MMC}2 ${DIR}/disk

 if [ "$CHESSY_SOURCE" ] ; then
  sudo tar xfp binary-tar.tar.lzma --lzma --strip-components=1 -C disk/
 else
  sudo tar xfp ${DIR}/armel-rootfs-* -C ${DIR}/disk/
 fi

 if [ "$CREATE_SWAP" ] ; then

  echo ""
  echo "Creating SWAP File"
  echo ""

  SPACE_LEFT=$(df ${DIR}/disk/ | grep ${MMC}2 | awk '{print $4}')

  let SIZE=$SWAP_SIZE*1024

  if [ $SPACE_LEFT -ge $SIZE ] ; then
   sudo dd if=/dev/zero of=${DIR}/disk/mnt/SWAP.swap bs=1M count=$SWAP_SIZE
   sudo mkswap ${DIR}/disk/mnt/SWAP.swap
   echo "/mnt/SWAP.swap  none  swap  sw  0 0" | sudo tee -a ${DIR}/disk/etc/fstab
   else
   echo "FIXME Recovery after user selects SWAP file bigger then whats left not implemented"
  fi
 fi

 cd ${DIR}/disk/
 sync
 sync
 cd ${DIR}/

 sudo umount ${DIR}/disk || true
}

function check_mmc {
 DISK_NAME="Disk|Platte"
 FDISK=$(sudo fdisk -l | grep "[${DISK_NAME}] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo fdisk -l | grep "[${DISK_NAME}] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
  [ "$REPLY" == "y" ] || exit
  echo ""
 else
  echo ""
  echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
  echo ""
  echo "sudo fdisk -l:"
  sudo fdisk -l | grep "[${DISK_NAME}] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function check_fs_type {
 IN_VALID_FS=1

 if test "-$FS_TYPE-" = "-ext2-"
 then
 RFS=ext2
 unset IN_VALID_FS
 fi

 if test "-$FS_TYPE-" = "-ext3-"
 then
 RFS=ext3
 unset IN_VALID_FS
 fi

 if test "-$FS_TYPE-" = "-ext4-"
 then
 RFS=ext4
 unset IN_VALID_FS
 fi

 if test "-$FS_TYPE-" = "-btrfs-"
 then
 RFS=btrfs
 unset IN_VALID_FS
 fi

 if [ "$IN_VALID_FS" ] ; then
   usage
 fi
}

function usage {
    echo "usage: $(basename $0) --mmc /dev/sdd"
cat <<EOF

required options:
--mmc </dev/sdX>
    Unformated MMC Card

Additional/Optional options:
-h --help
    this help

--rootfs <fs_type>
    ext2
    ext3 - <set as default>
    ext4
    btrfs

--boot_label <boot_label>
    boot partition label

--rfs_label <rfs_label>
    rootfs partition label

--swap_file <xxx>
    Creats a Swap file of (xxx)MB's

--xloader <xxx>
    specify a xloader file to use

--uboot <xxx>
    specify a uboot file to use

--mlo <xxx>
    specify a MLO file to use

EOF
exit
}

function checkparm {
    if [ "$(echo $1|grep ^'\-')" ];then
        echo "E: Need an argument"
        usage
    fi
}

# parse commandline options
while [ ! -z "$1" ]; do
    case $1 in
        -h|--help)
            usage
            MMC=1
            ;;
        --mmc)
            checkparm $2
            MMC="$2"
            check_mmc 
            ;;
        --rootfs)
            checkparm $2
            FS_TYPE="$2"
            check_fs_type 
            ;;
        --boot_label)
            checkparm $2
            BOOT_LABEL="$2"
            ;;
        --rfs_label)
            checkparm $2
            RFS_LABEL="$2"
            ;;
        --swap_file)
            checkparm $2
            SWAP_SIZE="$2"
            CREATE_SWAP=1
            ;;
        --chessy)
            CHESSY_SOURCE=1
            ;;
        --uboot)
	    checkparm $2
            UBOOT_FILE="$2"
            ;;
        --xloader)
	    checkparm $2
            XLOADER_FILE="$2"
            ;;
        --mlo)
	    checkparm $2
            MLO_FILE="$2"
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    usage
fi

 prepare_sources
 dl_xload_uboot
 cleanup_sd
 create_partitions
 populate_boot
 populate_rootfs

