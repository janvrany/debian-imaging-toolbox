#!/bin/bash
#
# Boot the system as container using systemd-nspawn
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
# None
: ${CONFIG_DEBIAN_ARCH:=amd64}
: ${CONFIG_DEBIAN_RELEASE:=bookworm}
: ${CONFIG_HOSTNAME:="${CONFIG_DEBIAN_RELEASE}-${CONFIG_DEBIAN_ARCH}"}

test -z "${CONFIG_RUN_IN_CONTAINER_BIND_USER+x}" || warn "CONFIG_RUN_IN_CONTAINER_BIND_USER is obsolete, IGNORING. Use -u USER option!"
test -z "${CONFIG_RUN_IN_CONTAINER_BIND_HOME+x}" || warn "CONFIG_RUN_IN_CONTAINER_BIND_HOME is obsolete, IGNORING. Use -h option!"

#
# Command line options
#
systemd_nspawn_opts=()

usage() { echo "Usage: $0 [-u USER|-h] [-x] IMAGE [COMMAND]" 1>&2; exit 1; }

while getopts ":u:hx" o; do
    case "${o}" in
        u)
            systemd_nspawn_opts+=("--bind-user=${OPTARG}")
            ;;
        h)
            systemd_nspawn_opts+=("--bind=${HOME}")
            ;;
        x)
            systemd_nspawn_opts+=("-x")
            ;;
    esac
done
shift $((OPTIND-1))

#
# Boot the system
#
if [ -z "$1" ]; then
    echo "usage: $(basename $0) [-u USER] <ROOT>"
    exit 1
fi

if [ -d "$1" ]; then
    image=--directory=$1
else
    image=--image=$1
fi

sudo systemd-nspawn --hostname "$CONFIG_HOSTNAME" \
                    --boot $image \
                    $systemd_nspawn_opts



