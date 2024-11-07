#!/bin/bash
#
# Run interactive shell "in the image" using systemd-nspawn
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_RUN_SHELL_BIND_USER:=no}
: ${CONFIG_RUN_SHELL_BIND_HOME:=no}

#
#
#
systemd_nspawn_opts=()


usage() { echo "Usage: $0 [-u USER] IMAGE [COMMAND]" 1>&2; exit 1; }

while getopts ":u:r:d:p:" o; do
    case "${o}" in
        u)
            systemd_nspawn_opts+=("-u" "${OPTARG}")
            ;;
    esac
done
shift $((OPTIND-1))


#
# Mount and umount the root
#
if [ -z "$1" ]; then
    usage
    exit 1
else
    ROOT_IMAGE=$1
    shift
fi

if [ "$CONFIG_RUN_SHELL_BIND_USER" == "yes" ]; then
    systemd_nspawn_opts+=("--bind-user=$USER")
elif [ "$CONFIG_RUN_SHELL_BIND_USER" == "no" ]; then
    true
elif [ -z "$CONFIG_RUN_SHELL_BIND_USER" ]; then
    true
else
    systemd_nspawn_opts+=("--bind-user=$CONFIG_RUN_SHELL_BIND_USER")
fi


if [ -d "$ROOT_IMAGE" ]; then
    systemd_nspawn_opts+=("--directory=$ROOT_IMAGE")
else
    systemd_nspawn_opts+=("--image=$ROOT_IMAGE")
fi

systemd_nspawn_opts+=("--hostname" "$(cat "$ROOT/etc/hostname")")
systemd_nspawn_opts+=("--bind-ro" "/etc/resolv.conf:/etc/resolv.conf")

if [ -z "$1" ]; then
    # Run interactive shell
    sudo systemd-nspawn "${systemd_nspawn_opts[@]}"
else
    # Run command inside the container
    sudo systemd-nspawn --hostname $(cat "$ROOT/etc/hostname") \
                        $image \
                        $bind_user \
                        --bind-ro /etc/resolv.conf:/etc/resolv.conf \
                        -a "$@"
fi