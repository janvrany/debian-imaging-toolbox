#!/bin/bash
#
# Bootstrap the debian
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/functions.sh"
config "$(dirname $0)/config.sh"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_DEBIAN_ARCH:=amd64}
: ${CONFIG_DEBIAN_RELEASE:=bullseye}
: ${CONFIG_DEBIAN_SOURCES:=}
: ${CONFIG_MACHINE_ID:=}
: ${CONFIG_BUILD_TMP_DIR:="$(dirname $0)/tmp"}
: ${CONFIG_BUILD_HOOK_DIR:="$(dirname $0)/build-hooks"}

if [ -z "$1" ]; then
    echo "usage: $(basename $0) <ROOT>"
    exit 1
fi

ensure_ROOT "$1"

# mkfs.ext3 creates lost+found directory, but `mmdebstrap` requires
# destination directory to be empty. So, remove `lost+found` is it exists
# and if it's empty...
if [ -d "${ROOT}/lost+found" ]; then
    if [ -z "$(ls -A ${ROOT}/lost+found)" ]; then
        sudo \
        rmdir "${ROOT}/lost+found"
    fi
fi

# ...and check then check again.
if [ ! -z "$(ls -A ${ROOT})" ]; then
    echo "Root directory is not empty: ${ROOT}"
    echo "Please remove all files an retry"
    exit 2
fi

#
# Setup global apt cache. Use (shared) host
# cache if host release and arch matches
#
cache_apt="${CONFIG_BUILD_TMP_DIR}/apt/archives"
if [ $(lsb_release -s -c) == $CONFIG_DEBIAN_RELEASE ]; then
    if dpkg-architecture --is $CONFIG_DEBIAN_ARCH; then
        cache_apt=/var/cache/apt/archives
    fi
fi
mkdir -p $cache_apt

#
# Care for Ubuntu
#
ubuntu_keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
ubuntu_keyring_arg=
ubuntu_upgrade_hook='echo " "'
case "$CONFIG_DEBIAN_RELEASE" in
    jammy|mantic|noble)
        if [ ! -f "$ubuntu_keyring" ]; then
            echo "WARNING: $ubuntu_keyring not found!"
            echo "WARNING: You may want to 'apt-get install ubuntu-keyring'"
        else
            ubuntu_keyring_arg="--keyring=$ubuntu_keyring"
        fi
        ubuntu_upgrade_hook="sed -i -e s/focal/$CONFIG_DEBIAN_RELEASE/g \$1/etc/apt/sources.list; \
                             chroot \$1 /usr/bin/apt-get update;
                             chroot \$1 /usr/bin/apt-get -y upgrade; \
                             chroot \$1 /usr/bin/apt-get -y autoremove \
                            "
        CONFIG_DEBIAN_RELEASE=focal
        if [ -z "$CONFIG_DEBIAN_SOURCES" ]; then
            CONFIG_DEBIAN_SOURCES="deb http://archive.ubuntu.com/ubuntu $CONFIG_DEBIAN_RELEASE main universe"
        fi
        ;;
    trusty|xenial|bionic|focal)
        if [ ! -f "$ubuntu_keyring" ]; then
            echo "WARNING: $ubuntu_keyring not found!"
            echo "WARNING: You may want to 'apt-get install ubuntu-keyring'"
        else
            ubuntu_keyring_arg="--keyring=$ubuntu_keyring"
        fi
        if [ -z "$CONFIG_DEBIAN_SOURCES" ]; then
            CONFIG_DEBIAN_SOURCES="deb http://archive.ubuntu.com/ubuntu $CONFIG_DEBIAN_RELEASE main universe"
        fi
        ;;
    *)
        ;;
esac

#
# Setup CONFIG_DEBIAN_SOURCES if not already
#
if [ -z "$CONFIG_DEBIAN_SOURCES" ]; then
    CONFIG_DEBIAN_SOURCES="deb http://deb.debian.org/debian $CONFIG_DEBIAN_RELEASE main contrib"
fi

#
# Make CONFIG_BUILD_TMP_DIR visisible to hooks
#
mkdir -p "$CONFIG_BUILD_TMP_DIR"
export CONFIG_BUILD_TMP_DIR

# Bootstrap!
sudo \
mmdebstrap \
    --variant=minbase \
    --architectures=$CONFIG_DEBIAN_ARCH \
    $ubuntu_keyring_arg \
    --skip=download/empty --skip=essential/unlink --skip=cleanup/apt \
    --setup="mkdir -p $(realpath $ROOT)/var/cache/apt/archives/" \
    --setup="sync-in $cache_apt /var/cache/apt/archives/" \
    --setup="ls $(realpath $ROOT)/var/cache/apt/archives/" \
    --customize-hook="${ubuntu_upgrade_hook}" \
    --hook-directory="${CONFIG_BUILD_HOOK_DIR}" \
    --customize-hook='if findmnt -n $1/etc/resolv.conf; then sudo umount $1/etc/resolv.conf; fi' \
    --customize-hook='ls $1/var/cache/apt/archives' \
    --customize-hook="sync-out /var/cache/apt/archives/ $cache_apt" \
    --customize-hook='chroot $1 apt clean' \
    --include=apt \
    $CONFIG_DEBIAN_RELEASE "$ROOT" \
    "$CONFIG_DEBIAN_SOURCES"

# For some reason, contents of "$ROOT/etc/machine-id" nor file
# "/var/lib/dbus/machine-id" do not survive mmdebstrap, so if
# CONFIG_MACHINE_ID set, we initialize it here. Sigh.
if [ ! -z "$CONFIG_MACHINE_ID" ]; then
    echo "$CONFIG_MACHINE_ID" | sudo tee "$ROOT/etc/machine-id"
    rm -f    "$ROOT/var/lib/dbus/machine-id"
    ln -r -s "$ROOT/etc/machine-id" "$ROOT/var/lib/dbus/machine-id"
fi
