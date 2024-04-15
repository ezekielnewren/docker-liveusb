
source $(dirname $0)/core.sh

cleanup() {
    losetup -d $BLOCK_DEVICE
}


image=$1
cmd="$2"

if [ "$cmd" == "" ]; then
    echo "no command specified to be run while the loopback device is mounted, exiting..."
    exit 1
fi

if [ $(losetup -a | grep -c /tmp/build/usb.img) -gt 0 ]; then
    echo "cannot setup loopback device for image $image as it's already being used by another loopback device"
    exit 2
fi

export BLOCK_DEVICE=$(losetup -Pf --show $image) || exit $?
trap cleanup SIGINT

$cmd "${@:3}"

cleanup

