#!/bin/bash

source $(dirname $0)/core.sh

if [ ! -b $BLOCK_DEVICE ]; then
    echo "the environment variable BLOCK_DEVICE must be a block device: $BLOCK_DEVICE"
    exit 1
fi

cleanup() {
    ec=$?
    echo
    echo
    echo
    if [ $ec -ne 0 ]; then
        echo -e "\e[31mbuild failed!\e[0m"
        if [ "$debug_mode" == "true" ]; then
            DEBUG
        fi
    fi

    if [ -d root/root ]; then
        echo "alias ll='ls -alF'" > root/root/.profile
    fi
    unmount_all $BUILD_DIR
    if [ "$FDE_NAME" != "" ]; then
        cryptsetup luksClose $FDE_NAME
    fi
    if [ ! -z "$ISO_BLOCK_DEVICE" ]; then
        losetup -d $ISO_BLOCK_DEVICE
    fi
    exit $ec
}




# Define the usage message
usage() {
  echo "Usage: $0 -f <file> -d <directory>"
  exit 1
}

# Initialize variables
export debug_mode="false"
export imsure="false"
export key_file=""

# Parse command-line options
while getopts "dyk:" opt; do
  case "$opt" in
    d) debug_mode="true" ;;
    y) imsure="true" ;;
    k) key_file="$OPTARG" ;;
    *) usage ;;
  esac
done


if [ "$BUILD_DIR" != "" ]; then
    cd $BUILD_DIR
else
    export BUILD_DIR=/tmp/build
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
fi

# https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86_64/alpine-extended-3.17.1-x86_64.iso

# https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.4-x86_64-minimal.iso

version_short="9"
version_long="$version_short.4"
url_base="https://download.rockylinux.org/pub/rocky/${version_short}/isos/x86_64"
# image="Rocky-${version_long}-x86_64-minimal.iso"
image="Rocky-${version_long}-x86_64-boot.iso"

info "download iso image"
wget -c $url_base/$image

trap cleanup SIGINT SIGTERM
export ISO_BLOCK_DEVICE=$(losetup -Pf --show $BUILD_DIR/$image) || cleanup


mkdir -p $BUILD_DIR/isop1 $BUILD_DIR/isop2
mount $(partition $ISO_BLOCK_DEVICE 1) $BUILD_DIR/isop1 || cleanup
mount $(partition $ISO_BLOCK_DEVICE 2) $BUILD_DIR/isop2 || cleanup

echo -e "This will wipe all data on device ${RED}$blkdev${NC}"
echo
fdisk -l $BLOCK_DEVICE
if [ "$imsure" != "true" ]; then
    echo
    confirm "Are you sure you want to continue?" || exit 3
fi

seconds=5
echo -e "you have ${RED}$seconds seconds${NC} to change your mind"
sleep $seconds
echo
echo "starting..."



ISO_SIZE_MB=$(($(stat -c%s "$image") / 1024 / 1024))

# Add some extra space (e.g., 200 MB) to account for any additional files in /boot
BOOT_SIZE_MB=$(($ISO_SIZE_MB + 200))


info "create partitions"
partprobe
sgdisk --zap $BLOCK_DEVICE || cleanup
dd if=/dev/zero bs=$((1<<20)) count=1 of=$BLOCK_DEVICE
partprobe
sgdisk --clear $BLOCK_DEVICE || cleanup
sgdisk --new 1::+512M             --typecode=1:ef00 $BLOCK_DEVICE || cleanup
sgdisk --new 2::+${BOOT_SIZE_MB}M --typecode=2:8300 $BLOCK_DEVICE || cleanup
sgdisk --new 3::                  --typecode=2:8300 $BLOCK_DEVICE || cleanup
sync
partprobe
sleep 1



info "format partitions"
mkfs.fat -F32 $(partition $BLOCK_DEVICE 1) || cleanup
export EFI_UUID=$(blkid -s UUID -o value $(partition $BLOCK_DEVICE 1)) || cleanup
mkfs.ext4 -F $(partition $BLOCK_DEVICE 2) || cleanup
export BOOT_UUID=$(blkid -s UUID -o value $(partition $BLOCK_DEVICE 2)) || cleanup
mkfs.ext4 -F $(partition $BLOCK_DEVICE 3) || cleanup
export KICKSTART_UUID=$(blkid -s UUID -o value $(partition $BLOCK_DEVICE 3)) || cleanup
sleep 1

fatlabel $(partition $BLOCK_DEVICE 1) "EFI" || cleanup
e2label  $(partition $BLOCK_DEVICE 2) "BOOT" || cleanup
e2label  $(partition $BLOCK_DEVICE 3) "KICKSTART" || cleanup

info "mount partitions"
mkdir -p root
chmod 000 root
mount UUID=$BOOT_UUID root || cleanup

mkdir -p root/boot
mount UUID=$EFI_UUID root/boot || cleanup

rsync -av --progress isop1/ root/ || cleanup
rsync -av --progress isop2/ root/boot || cleanup
rsync -av /copy/files/grub.cfg root/boot/EFI/BOOT/grub.cfg

if [ "$debug_mode" == "true" ]; then
    DEBUG
fi

info "cleanup ..."
cleanup
info "done"

