#!/bin/bash
#
# Install and configure firewalld.
# This should run last because it tries to guess
# which services to allow (currently only probes ssh and http(s))
#
source "$(dirname $0)/../functions.sh"
config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/../config-local.sh"
ensure_ROOT $1

#
# Config variables
#
# None

#
# Install firewalld
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
	firewalld
#
# Try to auto-detect services and enable them
#
if [ -f "$ROOT/etc/ssh/sshd_config" ]; then
	#
	#
	#
	sudo mkdir -p "$ROOT/run/sshd"
	sshd_port=$(chroot "${ROOT}" sshd -T | grep 'port ' | cut -d ' ' -f 2)
	if [ "$sshd_port" != "22" ]; then
		chroot "${ROOT}" firewall-offline-cmd --service=ssh --add-port=${sshd_port}/tcp
		chroot "${ROOT}" firewall-offline-cmd --service=ssh --remove-port=22/tcp
	fi
	chroot "${ROOT}" firewall-offline-cmd --zone=public --add-service=ssh
fi

if [ -d "$ROOT/etc/nginx" ]; then
	chroot "${ROOT}" firewall-offline-cmd --zone=public --add-service=http
	chroot "${ROOT}" firewall-offline-cmd --zone=public --add-service=https
fi