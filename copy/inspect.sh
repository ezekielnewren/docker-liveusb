
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

trap cleanup SIGINT SIGTERM

# mount partitions
if [ "$BLOCK_DEVICE" != "" ]; then
    if [ ! -b "$BLOCK_DEVICE" ]; then
        echo "$BLOCK_DEVICE is not a block device"
        exit 1
    fi

    mount $(partition $BLOCK_DEVICE 2) $mountpoint
    mount $(partition $BLOCK_DEVICE 1) $mountpoint/boot
fi

PS1="\e[31mINSPECT\e[0m:\w# " bash

cleanup

