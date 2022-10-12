#!/bin/bash
#
# Install and configure unstattended upgrades
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
# Install unstattended upgrades
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
	unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
' | sudo tee "$ROOT/etc/apt/apt.conf.d/51unattended-upgrades-local"
