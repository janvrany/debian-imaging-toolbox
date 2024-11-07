#!/bin/bash
#
# Install and configure OpenSSH server
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/../functions.sh"
config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/../config-local.sh"
ensure_ROOT $1

#
# Config variables
#
: ${CONFIG_SSHD_PORT:=22}

#
# Install OpenSSHD server
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
	openssh-server

#
# Older Debians (Buster and older) do not by default
# include config from sshd_config.d, so check and make it so.
#
if ! grep -q 'Include /etc/ssh/sshd_config.d/\*.conf' "$ROOT/etc/ssh/sshd_config"; then
	mkdir -p $ROOT/etc/ssh/sshd_config.d
	echo "
Include /etc/ssh/sshd_config.d/*.conf
" | sudo tee -a "$ROOT/etc/ssh/sshd_config"
fi

echo "
#
# !!! When changing port, also edit
#     /etc/systemd/system/ssh.socket.d/override.conf
#
Port $CONFIG_SSHD_PORT

AllowUsers $USER
Protocol 2
" | sudo tee "$ROOT/etc/ssh/sshd_config.d/hardening.conf"

sudo mkdir -p "$ROOT/etc/systemd/system/ssh.socket.d"
echo "
#
# !!! When changing port, also edit
#     /etc/ssh/sshd_config.d/hardening.conf
#
[Socket]
ListenStream=
ListenStream=$CONFIG_SSHD_PORT
" | sudo tee "$ROOT/etc/systemd/system/ssh.socket.d/override.conf"
