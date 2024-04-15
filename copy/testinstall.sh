source $(dirname $0)/core.sh

export BUILD_DIR=/tmp/build
mkdir -p $BUILD_DIR
cd $BUILD_DIR

image=$BUILD_DIR/usb.img
rm $image
truncate -s $((3<<30)) $image
echo -n asdf > /tmp/keyfile

mount_loopback.sh $image autoinstall.sh "${@:1}"


