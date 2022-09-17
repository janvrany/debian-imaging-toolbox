#!/bin/bash
#
# Install cronwrap from https://github.com/janvrany/cronwrap
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
# Install cronwrap
#
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
	python3 python3-pip
chroot "${ROOT}" pip install https://github.com/janvrany/cronwrap/archive/refs/heads/master.zip
