#!/bin/bash
#
# Run interactive shell "in the image" using systemd-nspawn
#
source "$(dirname $0)/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_RUN_SHELL_BIND_USER:=no}

#
# Mount and umount the root
#
if [ -z "$1" ]; then
    echo "usage: $(basename $0) <ROOT>"
    exit 1
else
    ROOT_IMAGE=$1
    shift
fi

if [ "$CONFIG_RUN_SHELL_BIND_USER" == "yes" ]; then
    bind_user=--bind-user=$USER
elif [ "$CONFIG_RUN_SHELL_BIND_USER" == "no" ]; then
    true
elif [ -z "$CONFIG_RUN_SHELL_BIND_USER" ]; then
    true
else
    bind_user=--bind-user=$CONFIG_RUN_SHELL_BIND_USER
fi

if [ -d "$ROOT_IMAGE" ]; then
    image=--directory=$ROOT_IMAGE
else
    image=--image=$ROOT_IMAGE
fi

if [ -z "$1" ]; then
    # Run interactive shell
    sudo systemd-nspawn --hostname $(cat "$ROOT/etc/hostname") \
                        $image \
                        $bind_user
else
    # Run command inside the container
    sudo systemd-nspawn --hostname $(cat "$ROOT/etc/hostname") \
                        $image \
                        $bind_user \
                        -a "$@"
fi