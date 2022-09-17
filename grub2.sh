#!/bin/bash
#
# Install Linux kernel and GRUB2 into disk image.
#
source "$(dirname $0)/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
# None

#
# Install Linux kernel and GRUB2
#
if [ -z "$1" ]; then
    echo "usage: $(basename $0) <ROOT>"
    exit 1
elif [ -d "$1" ]; then
	error "Invalid root filesystem image (directory): $1"
	exit 2
fi

tmp=$(realpath $(dirname $0))/tmp
mkdir -p $tmp

ensure_ROOT "$1"
sudo chroot "${ROOT}" apt-get --allow-unauthenticated -y install \
						linux-image-amd64 grub-pc
echo "
// See https://stackoverflow.com/questions/61327011/correct-way-to-exit-init-in-linux-user-mode
#include <unistd.h>
#include <sys/reboot.h>
int main(int argc, char *argv[]) {
  sync();
  reboot(RB_POWER_OFF);
}
" > "$ROOT/tmp/off.c"
gcc -static -o "$ROOT/tmp/off" "$ROOT/tmp/off.c"

echo '
#
# Enable serial console in Linux:
#
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=ttyS0"

#
# ...and also in GRUB:
#
GRUB_TERMINAL=console
' | sudo tee "$ROOT/etc/default/grub.d/console.cfg"

echo '
#
# Make root filesystem writable. Why the hell is
# this needed?
#
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX rw"
' | sudo tee "$ROOT/etc/default/grub.d/rw.cfg"

echo '
#
# Disable predictable network interface names.
# The rationale is that the image will likely run as
# VM or on some board with single NIC anyway and this
# makes it easier to configure network.
#
# See https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
#
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX net.ifnames=0"
' | sudo tee "$ROOT/etc/default/grub.d/ifnames.cfg"

echo "#!/bin/bash
set -x
update-grub2
grub-install /dev/vda
/tmp/off
" | sudo tee "$ROOT/tmp/grub-self-install.sh"
sudo chmod ugo+x "$ROOT/tmp/grub-self-install.sh"
umount_ROOT

sleep 1

root_dev=$(part_ROOT $1)
vmlinuz=$(guestfish -a "$1" -m $root_dev:/ readlink /vmlinuz)
initrd=$(guestfish -a "$1" -m $root_dev:/ readlink /initrd.img)

guestfish -a "$1" -m $root_dev:/ copy-out /$vmlinuz $tmp
guestfish -a "$1" -m $root_dev:/ copy-out /$initrd $tmp

rm -f $tmp/vmlinuz $tmp/initrd.img
mv $tmp/$(basename $vmlinuz) $tmp/vmlinuz
mv $tmp/$(basename $initrd) $tmp/initrd.img

qemu-system-x86_64 \
    -M q35 -m "512M" \
	-kernel "$tmp/vmlinuz" -initrd "$tmp/initrd.img" -append "root=/dev/vda1 rw console=ttyS0 init=/tmp/grub-self-install.sh" \
	-nographic \
	-drive if=none,id=drive0,cache=none,aio=native,file=$1 -device virtio-blk-pci,drive=drive0,scsi=off \
	-netdev user,id=hostnet0 -device virtio-net-pci,netdev=hostnet0
