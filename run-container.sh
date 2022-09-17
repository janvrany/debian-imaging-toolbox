#!/bin/bash
#
# Boot the system as container using systemd-nspawn
#
source "$(dirname $0)/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_RUN_IN_CONTAINER_BIND_USER:=no}

#
# Boot the system
#
if [ -z "$1" ]; then
    echo "usage: $(basename $0) <ROOT>"
    exit 1
fi

if [ "$CONFIG_RUN_IN_CONTAINER_BIND_USER" == "yes" ]; then
    bind_user=--bind-user=$USER
elif [ "$CONFIG_RUN_IN_CONTAINER_BIND_USER" == "no" ]; then
    true
elif [ -z "$CONFIG_RUN_IN_CONTAINER_BIND_USER" ]; then
    true
else
    bind_user=--bind-user=$CONFIG_RUN_IN_CONTAINER_BIND_USER
fi

if [ -d "$1" ]; then
    image=--directory=$1
else
    image=--image=$1
fi

sudo systemd-nspawn --hostname $(cat "$ROOT/etc/hostname") \
                    --boot $image \
                    $bind_user



