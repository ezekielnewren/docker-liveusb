#!/bin/bash

BLOCK_DEVICE=$1

if [ "$BLOCK_DEVICE" == "" ]; then
    echo "must specify a block device"
    exit 1
fi

if [ ! -b $BLOCK_DEVICE ]; then
    echo "$BLOCK_DEVICE is not a block device"
    exit 1
fi

cryptsetup luksDump $BLOCK_DEVICE >/dev/null; ec=$?
if [ $ec -ne 0 ]; then
    exit $ec
fi

BLOCK_DEVICE=`readlink -f $BLOCK_DEVICE`

opts="--batch-mode --pbkdf=pbkdf2 --pbkdf-force-iterations 1024 --hash sha256"

eval $(blkid $BLOCK_DEVICE | cut -d: -f2)
new_passphrase=$(python3 /opt/eckdf.py $UUID)

KEY_SLOT=1

tmp=$(cryptsetup luksDump --dump-json-metadata $BLOCK_DEVICE | jq ".keyslots.[\"$KEY_SLOT\"]")
if [ "$tmp" != "null" ]; then
    cryptsetup luksOpen --test-passphrase --key-file <(echo -n $new_passphrase) --key-slot $KEY_SLOT UUID=$UUID; ec=$?
    if [ $ec -eq 0 ]; then
        echo "Already enrolled"
        exit 0
    fi
fi

read -sp "Enter passphrase: " passphrase
echo
if [ "$tmp" != "null" ]; then
    echo -n "slot $KEY_SLOT is occupied, deleting..."
    cryptsetup luksKillSlot --key-file <(echo -n $passphrase) $BLOCK_DEVICE $KEY_SLOT
    echo "done"
fi
cryptsetup luksAddKey UUID=$UUID $opts --key-file <(echo -n $passphrase) --new-keyfile <(echo -n $new_passphrase) -S $KEY_SLOT
cryptsetup luksOpen --test-passphrase --key-file <(echo -n $new_passphrase) --key-slot $KEY_SLOT UUID=$UUID && echo correct || echo wrong

# cryptsetup luksOpen --test-passphrase --key-slot 1 UUID=$UUID && echo correct || echo wrong
# cryptsetup luksKillSlot $BLOCK_DEVICE 1
