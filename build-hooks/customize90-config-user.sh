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
        #
        # Copy contents of /etc/skel (which is not copied for some
        # reason)
        #
        cp -r $ROOT/etc/skel/.* "$HOME_IN_ROOT"

        #
        # Automatically start tmux when logging in over SSH
        #
        cat >> "$HOME_IN_ROOT/.profile" <<EOF

# Attach / run 'tmux' if we're connecting
# via SSH and 'tmux' is installed.
if [ ! -z "\$SSH_CLIENT" -a -z "\$TMUX" ]; then
    if which tmux; then
        exec tmux new-session -A -s main
    fi
fi
EOF

        #
        # Allow $USER to sudo as any user
        #
        cat >${ROOT}/etc/sudoers.d/$USER <<EOF
${USER}     ALL=(ALL:ALL) ALL
EOF
        #
        # Install SSH keys
        #
        for pubkey in id_rsa.pub id_dsa.pub; do
                if [ -r "$HOME/.ssh/$pubkey" ]; then
                        mkdir -p "$HOME_IN_ROOT/.ssh"
                        cat "$HOME/.ssh/$pubkey" >> "$HOME_IN_ROOT/.ssh/authorized_keys"
                        chmod -R go-rwx "$HOME_IN_ROOT/.ssh"
                fi
        done
        #
        # Disable root login
        #
        chroot "$ROOT" passwd --lock root

        #
        # Finally, make sure all files are owned by
        # $USER
        #
        chown -R $(id --user $USER):$(id --group $USER) "$HOME_IN_ROOT"
fi