
RED='\033[1;31m'
NC='\033[0m'

parent=$(dirname $BASH_SOURCE[0])

if [ $(echo $PATH | grep -c $parent) -eq 0 ]; then
    export PATH=$PATH:$parent
fi


DEBUG() {
    echo "exit shell to continue"
    PS1="\e[31mDEBUG\e[0m:\w# " bash
}
export DEBUG

CHROOT() {
    chroot root /bin/ash -c "source ~/.profile; cd /boot; PS1=\"\e[31mCHROOT\e[0m:\w# \" /bin/ash"
}
export CHROOT

partition() {
    device=$(readlink -f "$1")
    partno="$2"
    lsblk -po KNAME -n $device | grep -E "^${device}[^0-9]*${partno}$"
}
export -f partition

confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}
export -f confirm

unmount_all() {
    PREFIX=$1
    mount | tac | grep -E -o "$PREFIX[^ ]*" | xargs -l umount
}
export unmount_all

info() {
    msg=$1
    echo
    echo -e "\e[32m$msg\e[0m"
}


