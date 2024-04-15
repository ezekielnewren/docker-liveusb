#!/bin/bash

docker build -t alpine-grub-luks --network=host .

name=alpine-build

docker rm -f $name
if [ "$1" == "" ]; then
    docker run --name $name -it --rm -v /tmp:/tmp -v /dev:/dev -w /root --network=host --privileged alpine-grub-luks
else
    docker run --name $name -it --rm -v /tmp:/tmp -v /dev:/dev -w /root --network=host --privileged alpine-grub-luks "$1"
fi

