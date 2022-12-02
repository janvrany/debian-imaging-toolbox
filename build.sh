#!/bin/bash
#
# Bootstrap the debian
#
source "$(dirname $0)/functions.sh"
config "$(dirname $0)/config.sh"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_DEBIAN_ARCH:=amd64}
: ${CONFIG_DEBIAN_RELEASE:=bullseye}
: ${CONFIG_DEBIAN_SOURCES="deb http://deb.debian.org/debian $CONFIG_DEBIAN_RELEASE main contrib"}

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
cache_apt=$(realpath $(dirname $0))/tmp/apt/archives
if [ $(lsb_release -s -c) == $CONFIG_DEBIAN_RELEASE ]; then
    if dpkg-architecture --is $CONFIG_DEBIAN_ARCH; then
        cache_apt=/var/cache/apt/archives
    fi
fi
mkdir -p $cache_apt

# Bootstrap!
sudo \
mmdebstrap \
    --variant=minbase \
    --architectures=$CONFIG_DEBIAN_ARCH \
    --skip=download/empty --skip=essential/unlink --skip=cleanup/apt \
    --setup="mkdir -p $(realpath $ROOT)/var/cache/apt/archives/" \
    --setup="sync-in $cache_apt /var/cache/apt/archives/" \
    --setup="ls $(realpath $ROOT)/var/cache/apt/archives/" \
    --hook-directory=$(realpath $(dirname $0)/build-hooks) \
    --include=apt \
    $CONFIG_DEBIAN_RELEASE "$ROOT" \
    "$CONFIG_DEBIAN_SOURCES"

# Archive and cleanup downloaded packages
ls    $(realpath $ROOT)/var/cache/apt/archives/*.deb
if [ "$cache_apt" == "/var/cache/apt/archives" ]; then
    sudo cp -u $(realpath $ROOT)/var/cache/apt/archives/*.deb $cache_apt
else
    cp -u $(realpath $ROOT)/var/cache/apt/archives/*.deb $cache_apt
fi
sudo rm -f $(realpath $ROOT)/var/cache/apt/archives/*.deb