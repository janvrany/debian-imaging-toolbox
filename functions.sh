#
# A set of common functions to be used
# by both scripts and hooks.
#
set -ex

function error () {
    echo "ERROR: $1"
    exit 1
}

function warn () {
    echo "WARNING: $1"
    exit 1
}

#
# Load config from given file if it exists.
#
function config() {
    local config_file=$(realpath -s $1)
    if test -f $config_file; then
        source $config_file
        return 0
    else
        return 0
    fi
}

# Set USER, HOME and SSH_AUTH_SOCK.
#
# Since this can be used also from hook, USER
# HOME and SSH_AUTH_SOCK may be altered or missing.
# Even SUDO_USER may be `root`.
#
# In that case, we try harder to detect real user
# that called the mmdebstrap. using admittedly
# a super-hacky way...
if [ ! -z "$SUDO_USER" ]; then
    if [ "$SUDO_USER" == "root" ]; then
        if [ ! -z "$XAUTHORITY" ]; then
            USER_ID=$(echo "$XAUTHORITY" | cut -d / -f 4)
            USER=$(id --user --name "$USER_ID" 2>/dev/null || echo "$SUDO_USER")
        fi
    else
        USER_ID=$(id --user "$SUDO_USER")
        USER=$SUDO_USER
    fi
    HOME=$(grep $USER /etc/passwd | cut -d : -f 6)
fi

if [ -z "$SSH_AUTH_SOCK" ]; then
    if test -S /run/user/$USER_ID/keyring/ssh; then
        export SSH_AUTH_SOCK=/run/user/$USER_ID/keyring/ssh
    fi
fi

function sudo () {
    if [ "x$(id -u)" != "x0" ]; then
        echo "!!! Using SUDO for following command:"
        echo
        echo "    $@"
        echo
    fi
    /usr/bin/sudo "$@"
}

function ssh () {
    /usr/bin/ssh -F "$HOME/.ssh/config" "$@"
}

function scp () {
    /usr/bin/scp -F "$HOME/.ssh/config" "$@"
}


function confirm ()  {
  echo  -n "$1 [y/n/Ctrl-C]? "
  read answer
  finish="-1"
  while [ "$finish" = '-1' ]
  do
    finish="1"
    if [ "$answer" = '' ];
    then
      answer=""
    else
      case $answer in
        y | Y | yes | YES ) return 0;;
        n | N | no | NO ) return 1;;
        *) finish="-1";
           echo -n 'Invalid response -- please reenter:';
           read answer;;
       esac
    fi
  done
}


# Set ROOT variable to a full patch to Debian root
# filesystem.
#
# If the parameter is a directory, then this directory is returned.
#
# Returns 0 if ROOT directory has been set, 1 otherwise

function ensure_ROOT() {
    if [ -z "$1" ]; then
        echo "E: Invalid ROOT (no ROOT directory, device or file given)"
        return 1
    elif [ -d "$1" ]; then
        ROOT=$(realpath "$1")
        mount_ROOT "$1"
        return 0
    elif [ \( \( -f "$1" \) -a \( -w "$1" \) \) -o \( -b "$1" \) ]; then
        ROOT=$(realpath $(mktemp -d))
        mount_ROOT "$1"
        return 0
    else
        # echo "E: Invalid ROOT (not a directory): $1"
        # return 1
        ROOT=$(realpath $(mktemp -d))
        mount_ROOT "$1"
        return 0

    fi
}

# Print the root partition name of given disk image
function part_ROOT() {
    local parts
    local root_part
    parts=$(guestfish -a "$1" run : list-filesystems | grep ext4 | cut -d : -f 1)
    for part in $parts; do
        if [ -z "$root_part" ]; then
            root_part=$part
        else
            echo "E: Multiple ext4 filesystems in '$1': $root_part and $part"
            return 1
        fi
    done
    case "$root_part" in
        /dev/sda*)
            echo "$root_part"
            ;;
        *)
            echo "E: Unsupported root partition type in '$1': $ROOT_PART"
            return 1
    esac
    return 0
}

# Mounts Debian root filesystem on given device file
# (passed in $1) into directory in ROOT variable.
function mount_ROOT() {
    if findmnt "${ROOT}" > /dev/null; then
        echo echo "I: already mounted (${ROOT})"
    else
        echo "I: mounting $1 into ${ROOT}"
        if [ -d "$1" ]; then
            sudo mount -o bind "$1" "${ROOT}"
        elif [ -b "$1" ]; then
            sudo mount "$1" "${ROOT}"
        else
            ROOT_PART=$(part_ROOT $1)
            case "$ROOT_PART" in
                /dev/sda[1-9])
                    # Check format. If image is 'raw', use losetup, otherwise
                    # use guestmount
                    if [ -f "$1" -a "$(qemu-img info $1 | grep 'file format' | cut -d ' ' -f 3)" == "raw" ]; then
                        # Following is only to ensure auth token is valid
                        sudo echo
                        ROOT_LO_DEV=$(/usr/bin/sudo losetup --find --show $1)
                        sudo kpartx -a "${ROOT_LO_DEV}"
                        ROOT_LO_PART=$(echo $ROOT_PART | sed -e "s@/dev/sda@/dev/mapper/${ROOT_LO_DEV##*/}p@g")
                        sudo mount "$ROOT_LO_PART" "$ROOT"
                    else
                        sync
                        sudo \
                        guestmount -a "$1" -m $ROOT_PART:/:acl,user_xattr -o allow_other -o kernel_cache -w "${ROOT}"
                    fi
                    ;;
                /dev/sda)
                    # Whole device, mount using mount -o loop as this is way faster
                    # than guestmount
                    sudo mount -o loop "$1" "${ROOT}"
                    ;;
                *)
                    echo "E: Unsupported root partition type in '$1': $ROOT_PART"
                    exit 1
            esac
        fi
        if [ -d "${ROOT}/etc" ]; then
            sudo mount -o bind,ro "/etc/resolv.conf" "${ROOT}/etc/resolv.conf"
        fi
        trap umount_ROOT EXIT
    fi
}

function umount_ROOT() {
    if [ -d "${ROOT}/proc/self" ]; then
        sleep 1
        sudo umount "${ROOT}/proc"
    fi
    if findmnt -n "${ROOT}/etc/resolv.conf"; then
        sleep 1
        sudo umount "${ROOT}/etc/resolv.conf"
    fi
    if grep "${ROOT}" /etc/mtab > /dev/null; then
        echo "I: umounting '${ROOT}'"
        fstype=$(grep "${ROOT}" /etc/mtab | cut -d ' ' -f 3)
        fssource=$(findmnt -n --output=source "${ROOT}")
        if [ "$fstype" == "fuse" ]; then
            # sudo \
            #guestunmount "${ROOT}"
            sudo umount "$ROOT"
        else
            sudo umount "$ROOT"
        fi
        case "$fssource" in
            /dev/mapper/loop*)
                ROOT_LO_DEV=$(echo "$fssource" | sed -e s#/dev/mapper/#/dev/#g -e 's#p[0-9]$##g')
                sudo kpartx -d "${ROOT_LO_DEV}"
                sudo losetup -d "${ROOT_LO_DEV}"
                ;;
            *)
                ;;
        esac

    fi
}