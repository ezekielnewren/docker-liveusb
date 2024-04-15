
source $(dirname $0)/core.sh

partition() {
    device="$1"
    partno="$2"
    lsblk -po KNAME -n $device | grep -E "[^0-9]${partno}$"
}
export -f partition

cleanup() {
    unmount_all $mountpoint
}


export mountpoint=$1

if [ $(id -u) -ne 0 ]; then
    echo run as root
    exit 1
fi

if [ "$mountpoint" == "" ]; then
    echo "you must specify a mountpoint"
    exit 1
fi

if [ ! -d "$mountpoint" ]; then
    echo "not a directory '$mountpoint'"
    exit 1
fi

# mount partitions
if [ "$BLOCK_DEVICE" != "" ]; then
    if [ ! -b "$BLOCK_DEVICE" ]; then
        echo "$BLOCK_DEVICE is not a block device"
        exit 1
    fi

    mount $(partition $BLOCK_DEVICE 2) $mountpoint
    mount $(partition $BLOCK_DEVICE 2) $mountpoint/boot
fi

# mount special filesystems
mount --bind /proc $mountpoint/proc/
mount --bind /sys $mountpoint/sys/
mount --bind /dev $mountpoint/dev/
trap cleanup SIGINT

chroot $mountpoint /bin/ash -l

cleanup

