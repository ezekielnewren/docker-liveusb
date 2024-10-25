#!/bin/bash

docker build -t rockylive --network=host .

name=rockylive-build

docker rm -f $name
if [ "$1" == "" ]; then
    docker run --name $name -it --rm -v /tmp:/tmp -v /dev:/dev -w /root --network=host --privileged rockylive
else
    docker run --name $name -it --rm -v /tmp:/tmp -v /dev:/dev -w /root --network=host --privileged rockylive "$1"
fi

