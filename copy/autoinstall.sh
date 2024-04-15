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

info "install mandatory software"
install_mandatory

# https://dl-cdn.alpinelinux.org/alpine/v3.17/releases/x86_64/alpine-extended-3.17.1-x86_64.iso

version_short="3.19"
version_long="$version_short.0"
url_base="https://dl-cdn.alpinelinux.org/alpine/v$version_short/releases/x86_64"
archive_rootfs="alpine-minirootfs-$version_long-x86_64.tar.gz"
#archive_netboot="alpine-netboot-3.17.1-x86_64.tar.gz"
#archive_extended="alpine-extended-3.17.1-x86_64.iso"

#export url_ipxe="http://boot.ipxe.org/ipxe.efi"

info "download archives"
for archive in $archive_rootfs; do
    wget -c $url_base/$archive
done

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

trap cleanup SIGINT

info "create partitions"
partprobe
sgdisk --zap $BLOCK_DEVICE || cleanup
dd if=/dev/zero bs=$((1<<20)) count=1 of=$BLOCK_DEVICE
partprobe
sgdisk --clear $BLOCK_DEVICE || cleanup
sgdisk --new 1::+512M $BLOCK_DEVICE || cleanup
sgdisk -t 1:ef00 $BLOCK_DEVICE || cleanup
sgdisk --new 2:: $BLOCK_DEVICE || cleanup
sync
partprobe

sleep 1


info "format partitions"
mkfs.fat -F32 $(partition $BLOCK_DEVICE 1) || cleanup
export BOOT_UUID=$(blkid -s UUID -o value $(partition $BLOCK_DEVICE 1)) || cleanup
if [[ ! -z "$key_file" ]] && [[ -f $key_file ]]; then
    info "encrypting $(partition $BLOCK_DEVICE 2)"
    cryptsetup luksFormat --batch-mode --key-file $key_file $(partition $BLOCK_DEVICE 2) || cleanup
    sleep 1
    export FDE_UUID=$(blkid -s UUID -o value $(partition $BLOCK_DEVICE 2)) || cleanup
    export FDE_NAME="luks-$FDE_UUID"
    cryptsetup luksOpen --key-file $key_file UUID=$FDE_UUID $FDE_NAME || cleanup
    sleep 1
    mkfs.ext4 -F /dev/mapper/$FDE_NAME || cleanup
    export ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/$FDE_NAME) || cleanup
else
    mkfs.ext4 -F $(partition $BLOCK_DEVICE 2) || cleanup
    export ROOT_UUID=$(blkid -s UUID -o value $(partition $BLOCK_DEVICE 2)) || cleanup
fi


sleep 1


info "mount partitions"
mkdir -p root
chmod 000 root
mount UUID=$ROOT_UUID root || cleanup

mkdir -p root/boot
mount UUID=$BOOT_UUID root/boot || cleanup
# mkdir -p root/boot/efi

info "extract root filesystem"
pushd root
tar -xf ../$archive_rootfs || cleanup
popd
sed -i 's/^root:[^:]*:/root::/' root/etc/passwd

info "copy custom files"
rsync -rlv /copy/files/ root/ || cleanup
rsync -rlv /copy root/ || cleanup

info "prepare chroot"
mount -o bind /dev root/dev || cleanup
# echo "alias ll='ls -alF'" > root/root/.profile || cleanup

info "configure /etc/fstab.json"
sed -i "s#ROOT_UUID#UUID=$ROOT_UUID#g" root/etc/fstab.json
sed -i "s#BOOT_UUID#UUID=$BOOT_UUID#g" root/etc/fstab.json
if [[ ! -z "$key_file" ]] && [[ -f $key_file ]]; then
    info "configure luks"
    sed -i "s#FDE_UUID#UUID=$FDE_UUID#g" root/etc/fstab.json
    sed -i "s#FDE_NAME#$FDE_NAME#g" root/etc/fstab.json
else
    tmp=$(jq -Mc 'del(.["/"].fde)' root/etc/fstab.json)
    echo $tmp | jq . > root/etc/fstab.json
fi
if [[ ! -f root/etc/fstab.json ]] || [[ $(wc -c root/etc/fstab.json | cut -d' ' -f1) -eq 0 ]]; then
    echo "empty or missing root/etc/fstab.json file"
    cleanup
fi

## we still need /etc/fstab to mount /boot properly
sed -i "s#ROOT_UUID#UUID=$ROOT_UUID#g" root/etc/fstab
sed -i "s#BOOT_UUID#UUID=$BOOT_UUID#g" root/etc/fstab




info "install operating system"
## install linux-firmware-none if no hardware support is desired
chroot root /bin/ash -c "apk add openrc alpine-base" || cleanup

info "install and configure grub"
grub-install --target=x86_64-efi --efi-directory=root/boot --boot-directory=root/boot --removable || cleanup
# sed -i "s/ROOT_UUID/$ROOT_UUID/g" root/boot/grub/grub.cfg || cleanup
sed -i "s/VERSION/$version_short/g" root/boot/grub/grub.cfg || cleanup
cat root/boot/grub/grub.cfg

info "configure initramfs"
chroot root /bin/ash -c "apk add cryptsetup" || cleanup
## verify that etc/fstab.json
## zcat /boot/initramfs-lts | cpio -t | grep -E "etc/fstab.json"
## extract a specific file to stdout
## zcat /boot/initramfs-lts | cpio --to-stdout -i etc/fstab.json 2>/dev/null

info "device manager setup"
chroot root /bin/ash -c "apk add lshw usbutils pciutils dbus" || cleanup
## device manager
chroot root /bin/ash -c "rm /etc/init.d/mdev"
chroot root /bin/ash -c "apk add eudev" || cleanup
chroot root /bin/ash -c "rc-update add udev sysinit" || cleanup
# chroot root /bin/ash -c "rc-update add mdev sysinit" || cleanup
chroot root /bin/ash -c "rc-update add hwdrivers sysinit" || cleanup
chroot root /bin/ash -c "rc-update add acpid sysinit" || cleanup
chroot root /bin/ash -c "rc-update add dbus boot" || cleanup
chroot root /bin/ash -c "rc-update add modules boot" || cleanup



info "install and enable network tools"
chroot root /bin/ash -c "apk add bridge-utils networkmanager networkmanager-wifi iwd iw hostapd awall dhclient" || cleanup
chroot root /bin/ash -c "rc-update add iwd boot" || cleanup
## the service 'networking' MUST not be running
chroot root /bin/ash -c "rc-update del networking sysinit"
chroot root /bin/ash -c "rc-update del networking boot"
chroot root /bin/ash -c "rc-update del networking default"
## enable the network manager
chroot root /bin/ash -c "rc-update add networkmanager boot" || cleanup

## /etc/NetworkManager/NetworkManager.conf
##     [device]
##     wifi.backend=iwd
## /etc/iwd/main.conf
##     [General]
##     AddressRandomization=disabled

chroot root /bin/ash -c "apk add linux-lts" || cleanup

info "install nice to have packages"
chroot root /bin/ash -c "apk add grep lsblk man-pages cpio acpi parted openssh-client xz gzip bash file nano rsync findutils" || cleanup

info "smart card tools"
chroot root /bin/ash -c "apk add jq yubikey-manager python3-dev py3-pip pcsc-lite-dev swig g++" || cleanup

info "call update-initramfs"
chroot root /bin/ash -c "update-initramfs"

if [ "$debug_mode" == "true" ]; then
    DEBUG
fi

info "cleanup ..."
cleanup
info "done"





