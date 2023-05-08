#!/bin/bash
#
# Add user (same as user who run the build) and
#
# * install its ssh pubkey
# * add it to sudoers
# * add it to the `sudo` and `adm` groups
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/../functions.sh"
config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/../config-local.sh"
ensure_ROOT $1

#
# Config variables
#
# None

#
# Create and setup user
#
chroot "${ROOT}" apt install -y sudo

if [ "$USER" != "root" ]; then
        echo "Creating user $USER..."
        chroot "${ROOT}" groupadd --gid=$(id --group $USER) $(id --group --name $USER) || true
        #chroot "${ROOT}" useradd \
        useradd --root "${ROOT}" \
                --create-home \
                --uid $(id --user $USER) \
                --gid=$(id --group $USER) \
                --groups sudo,adm \
                --password "$(sudo grep $USER /etc/shadow | cut -d : -f 2)" \
                $USER
        #
        # No, do not expire the password since user cannot
        # set the same password again.
        #
        # chroot "${ROOT}" /usr/bin/passwd --expire $USER
        chroot "${ROOT}" /usr/bin/chsh -s /bin/bash $USER

        HOME_IN_ROOT="$ROOT/$(grep $USER "${ROOT}/etc/passwd" | cut -d : -f 6)"
        cat >${ROOT}/etc/sudoers.d/$USER <<EOF
${USER}     ALL=(ALL:ALL) ALL
EOF
        # Install SSH keys
        for pubkey in id_rsa.pub id_dsa.pub; do
                if [ -r "$HOME/.ssh/$pubkey" ]; then
                        mkdir -p "$HOME_IN_ROOT/.ssh"
                        cat "$HOME/.ssh/$pubkey" >> "$HOME_IN_ROOT/.ssh/authorized_keys"
                        chmod -R go-rwx "$HOME_IN_ROOT/.ssh"
                        chown -R $(id --user $USER) "$HOME_IN_ROOT/.ssh"
                fi
        done
        # Disable root login
        chroot "$ROOT" passwd --lock root
fi
