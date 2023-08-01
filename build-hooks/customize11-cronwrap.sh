#!/bin/bash
#
# Install cronwrap from https://github.com/janvrany/cronwrap
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/../functions.sh"
config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/../config-local.sh"
ensure_ROOT $1

#
# Config variables
#
: ${CONFIG_CRONWRAP_INSTALL_DIR:=/opt/cronwrap}

# build-essential is needed to build Mercurial's native code
chroot "${ROOT}" /usr/bin/apt-get --allow-unauthenticated -y install \
	python3 python3-dev python3-pip build-essential virtualenv

#
# Create virtualenv for Mercurial to make it self-contained
#
chroot "${ROOT}" /usr/bin/virtualenv "${CONFIG_CRONWRAP_INSTALL_DIR}"

#
# Install Mercurial
#
chroot "${ROOT}" "${CONFIG_CRONWRAP_INSTALL_DIR}/bin/pip" install \
	https://github.com/janvrany/cronwrap/archive/refs/heads/master.zip
(cd "${ROOT}/usr/local/bin" && ln -s "../../../${CONFIG_CRONWRAP_INSTALL_DIR}/bin/cronwrap" .)