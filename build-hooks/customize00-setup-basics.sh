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
: ${CONFIG_TIMEZONE:=$(cat /etc/timezone)}

#
#
# Install package signing keys for Debian ports
#
# for key_id in B523E5F3FC4E5F2C 8D69674688B6CB36; do
#     sudo mkdir -p "$ROOT/root/.gnupg"
#     sudo gpg --no-default-keyring --primary-keyring "$ROOT/root/.gnupg/pubring.kbx" \
#              --keyserver keyserver.ubuntu.com --recv-key $key_id
#     sudo gpg --no-default-keyring --primary-keyring "$ROOT/root/.gnupg/pubring.kbx" \
#              --export $key_id | sudo tee -a "$ROOT/etc/apt/trusted.gpg.d/debian-$key_id.gpg"
# done

#
# Install base packages
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated update
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
    adduser base-files base-passwd bash bsdutils \
    coreutils dash netbase \
    debianutils diffutils dpkg e2fsprogs findutils gpgv grep gzip \
    hostname init-system-helpers libbz2-1.0 libc-bin libc6 libgcc1 \
    libgmp10 liblz4-1 liblzma5 libstdc++6 login mawk \
    mount passwd perl-base sed tar \
    tzdata util-linux zlib1g nano wget busybox net-tools \
    iproute2 iputils-ping ca-certificates less \
    apt-utils openssh-client \
    sudo bash-completion tmux adduser acl ethtool \
    procps udev locales zip unzip \
    lsb-release dbus man
    # libgnutls30 \

#
# Install systemd
#

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
        systemd systemd-sysv libnss-resolve
    chroot "${ROOT}" mount -t proc proc /proc
else
    chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
        systemd systemd-sysv libnss-resolve
fi
chroot "${ROOT}" dpkg --configure -a

#
# Configure systemd-resolved.
#
sudo mkdir "$ROOT/etc/systemd/resolved.conf.d"
echo "
[Resolve]
# Quad9:      9.9.9.9 2620:fe::fe
# Cloudflare: 1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001
# Google:     8.8.8.8 8.8.4.4 2001:4860:4860::8888 2001:4860:4860::8844
FallbackDNS=9.9.9.9 2620:fe::fe 1.1.1.1 2606:4700:4700::1111
" | sudo tee "$ROOT/etc/systemd/resolved.conf.d/fallback.conf"
# Make /etc/resolv.conf a link to systemd-resolved managed file. On newer Debian versions
# (newer than Bullseye) this is done automagically as part of package installation.
# On older systems, it has (?) to be done manually. Hence the check.
if test ! -L "$ROOT/etc/resolv.conf"; then
    (cd "$ROOT/etc" && sudo rm -f resolv.conf && sudo ln -s ../run/systemd/resolve/resolv.conf)
fi
# Now, we have to mount real resolv.conf over (symlinked, systemd-resolved-managed resolv.conf)
# in currently being built chROOT to make sure name resolution is still working (since symlinked
# file does not exist yet or does not contain sensible information).
sudo mount -o bind "/etc/resolv.conf" "$ROOT/etc/resolv.conf"

#
# Install systemd-timesyncd
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
    systemd-timesyncd

#
# Configure machine ID. Note, that for some reason, contents of this
# file does not survive mmdebstrap, so if CONFIG_MACHINE_ID set, we
# initialize $ROOT/etc/machine-id in `build.sh`.
#
# See https://wiki.debian.org/MachineId
#
touch    "$ROOT/etc/machine-id"

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
# Configure timezone
#
echo "$CONFIG_TIMEZONE" | sudo tee "$ROOT/etc/timezone"
rm -f "${ROOT}/etc/localtime"
chroot "${ROOT}" ln -s "/usr/share/zoneinfo/$CONFIG_TIMEZONE" "/etc/localtime"

#
# Setup Debian security repo and update
#
if grep debian "$ROOT/etc/apt/sources.list" > /dev/null; then
    if [ "$CONFIG_DEBIAN_RELEASE" != "sid" ]; then
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
" | sudo tee "$ROOT/etc/systemd/network/99-$CONFIG_DEFAULT_NET_IFACE.network"
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
