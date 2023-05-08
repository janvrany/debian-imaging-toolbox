#!/bin/bash
#
# Install base packages and perform basic configuration:
#
#  * set hostname and update /etc/hosts
#  * setup security updates and update system
#  * configute default network interface
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/../functions.sh"
config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/../config-local.sh"
ensure_ROOT $1

#
# Config variables
#
: ${CONFIG_HOSTNAME:=debian}
: ${CONFIG_DEFAULT_NET_IFACE:=eth0}
: ${CONFIG_MACHINE_ID:=$(dbus-uuidgen)}

#
# Install base packages
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated update
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
    isc-dhcp-client adduser base-files base-passwd bash bsdutils \
    coreutils dash netbase \
    debianutils diffutils dpkg e2fsprogs findutils gpgv grep gzip \
    hostname init-system-helpers libbz2-1.0 libc-bin libc6 libgcc1 \
    libgmp10 liblz4-1 liblzma5 libstdc++6 login mawk \
    mount passwd perl-base sed tar \
    tzdata util-linux zlib1g nano wget busybox net-tools \
    iputils-ping ca-certificates less \
    apt-utils openssh-client \
    sudo bash-completion tmux adduser acl ethtool \
    procps udev locales zip unzip \
    lsb-release dbus man
    # libgnutls30 \

# When installing systemd, we have to umount /proc in
# chroot. This is because setting ACLs on guestmount-mounted
# filesystem does not work - despite using acl,user_xattr ext4
# options. Umounting /proc causes postinst script to skip
# ACL setting.
#
# See https://salsa.debian.org/systemd-team/systemd/-/blob/debian/master/debian/systemd.postinst#L46-L53
#
# Sigh!
if findmnt "${ROOT}"; then
    chroot "${ROOT}" umount /proc
    chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
        systemd systemd-sysv
    chroot "${ROOT}" mount -t proc proc /proc
else
    chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
        systemd systemd-sysv
fi

chroot "${ROOT}" dpkg --configure -a

#
# Configure machine ID
# See https://wiki.debian.org/MachineId
#
echo "$CONFIG_MACHINE_ID" | sudo tee "$ROOT/etc/machine-id"
echo "$CONFIG_MACHINE_ID" | sudo tee "$ROOT/var/lib/dbus/machine-id"

#
# Configure hostname and /etc/hosts
#
echo "$CONFIG_HOSTNAME" > "$ROOT/etc/hostname"
hostname_only=${CONFIG_HOSTNAME%%.*}
hostname_fqdn=${CONFIG_HOSTNAME}
if [ "x$hostname_only" == "x$hostname_fqdn" ]; then
    sudo sed -i -e "s/localhost/localhost $hostname_only/g" "$ROOT/etc/hosts"
else
    sudo sed -i -e "s/localhost/localhost $hostname_only $hostname_fqdn/g" "$ROOT/etc/hosts"
fi

#
# Setup Debian security repo and update
#
if grep debian "$ROOT/etc/apt/sources.list" > /dev/null; then
    if [ "$DISTRIB_CODENAME" != "sid" ]; then
        suites=$(grep '^deb' "$ROOT/etc/apt/sources.list" | tail -n 1 | cut -d ' ' -f 4,5,6,7,8)
        codename=$(grep '^deb' "$ROOT/etc/apt/sources.list" | tail -n 1 | cut -d ' ' -f 3)
        echo "deb http://security.debian.org/debian-security $codename-security $suites" | sudo tee -a "$ROOT/etc/apt/sources.list"
    fi
elif grep ubuntu "$ROOT/etc/apt/sources.list" > /dev/null; then
    suites=$(grep '^deb' "$ROOT/etc/apt/sources.list" | tail -n 1 | cut -d ' ' -f 4,5,6,7,8)
    codename=$(grep '^deb' "$ROOT/etc/apt/sources.list" | tail -n 1 | cut -d ' ' -f 3)
    echo "deb http://security.ubuntu.com/ubuntu $codename-security $suites" | sudo tee -a "$ROOT/etc/apt/sources.list"
fi
chroot "$ROOT" apt update
chroot "$ROOT" apt upgrade --allow-unauthenticated -y

#
# Configure eth0
#
if [ -d "$ROOT/etc/network/interfaces.d" ]; then
    # Use "old" Debian-style config
echo "
# auto $CONFIG_DEFAULT_NET_IFACE
allow-hotplug $CONFIG_DEFAULT_NET_IFACE
iface $CONFIG_DEFAULT_NET_IFACE inet dhcp
" | sudo tee "$ROOT/etc/network/interfaces.d/$CONFIG_DEFAULT_NET_IFACE"
elif [ -d "$ROOT/etc/systemd/network" ]; then
    # Use "modern" systemd-networkd config
echo "
[Match]
Name=$CONFIG_DEFAULT_NET_IFACE

[Network]
DHCP=yes
" | sudo tee "$ROOT/etc/systemd/network/$CONFIG_DEFAULT_NET_IFACE.network"
    chroot "$ROOT" systemctl enable systemd-networkd.service
fi

# #
# # Configure host0
# #
# echo "
# #
# # Interface host0 is used by systemd-nspawn when using
# # --network-veth. It is configured here to make make network
# # automagically work when running in container created by
# # systemd-nspawn.
# #
# allow-hotplug host0
# iface host0 inet dhcp
# " | sudo tee "$ROOT/etc/network/interfaces.d/host0"
