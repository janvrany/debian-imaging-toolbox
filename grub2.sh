#!/bin/bash
#
# Install Linux kernel and GRUB2 into disk image.
#
# This script currently supports only PCs with (legacy) BIOS.
# Other architectures and/or UEFI is not supported yet.
#
# 
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_GRUB_CMDLINE_LINUX_CUSTOM:=}
: ${CONFIG_BUILD_TMP_DIR:="$(dirname $0)/../tmp"}


#
# Options
#
usage() {
	echo "Install GRUB bootloader given the disk image.

Usage: $0 [-h] [-g] IMAGE

  -g ... Use to make image bootable on wide range of hardware and virtual machines.
         Without -g, image is optimized to boot quickly on KVM/QEMU virtual machines.

  -h ... Print this message.
" 1>&2;
}

optimize_for_kvm_vm=yes

while getopts ":gh" o; do
    case "${o}" in
        g)
            optimize_for_kvm_vm=no
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: ${OPTARG}"
            ;;
    esac
done
shift $((OPTIND-1))

#
# Install Linux kernel and GRUB2
#
if [ -z "$1" ]; then
    usage
    exit 1
elif [ -d "$1" ]; then
	error "Invalid root filesystem image (directory): $1"
	usage
	exit 2
fi

tmp="$CONFIG_BUILD_TMP_DIR"
mkdir -p $tmp

ensure_ROOT "$1"

if [ -r "$ROOT/etc/lsb-release" ]; then
    source "$ROOT/etc/lsb-release"
else
    DISTRIB_ID=$(sudo chroot "${ROOT}" lsb_release -s -i)
fi

if [ "$DISTRIB_ID" == "Ubuntu" ]; then
	kernel_pkg=linux-image-generic
else
	kernel_pkg=linux-image-amd64
fi


sudo chroot "${ROOT}" apt-get --allow-unauthenticated -y install \
						"$kernel_pkg" initramfs-tools zstd grub-pc
if [ "$optimize_for_kvm_vm" == "yes" ]; then
	sudo chroot "${ROOT}" apt-get --allow-unauthenticated -y install \
		qemu-guest-agent
fi
sudo chroot "${ROOT}" apt-get clean

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
# Disable os prober. There are no other systems.
#
GRUB_DISABLE_OS_PROBER=true
' | sudo tee "$ROOT/etc/default/grub.d/os-prober.cfg"

echo '
#
# Make root filesystem writable. Why the hell is
# this needed?
#
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX rw"
' | sudo tee "$ROOT/etc/default/grub.d/rw.cfg"

echo '
#
# Always include virtio_blk module in initramfs
#
virtio_blk"
' | sudo tee -a "$ROOT/etc/initramfs-tools/modules"

if [ ! -z "$CONFIG_GRUB_CMDLINE_LINUX_CUSTOM" ]; then
echo "
#
# Custom linux cmdline options
#
GRUB_CMDLINE_LINUX=\"\$GRUB_CMDLINE_LINUX $CONFIG_GRUB_CMDLINE_LINUX_CUSTOM\"
" | sudo tee "$ROOT/etc/default/grub.d/custom.cfg"
fi

#
# Following options are used only when the image is intedent
# to run on KVM/QEMU VMs only.
#

if [ "$optimize_for_kvm_vm" == "yes" ]; then

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
# Disable predictable network interface names.
# The rationale is that the image will likely run as
# VM or on some board with single NIC anyway and this
# makes it easier to configure network.
#
# See https://www.freedesktop.org/wiki/Software/systemd/PredictableNetworkInterfaceNames/
#
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX net.ifnames=0"
' | sudo tee "$ROOT/etc/default/grub.d/ifnames.cfg"

echo '
#
# Set timeout to 1. This saves us 4 secs when booting, especially
# handy when used as start-on-demand CI build node.
#
GRUB_TIMEOUT=1
' | sudo tee "$ROOT/etc/default/grub.d/timeout.cfg"

echo '
#
# Only include required modules in initramfs. This significantly
# reduces the size of initramfs and speeds up boot. This is especially
# handy when used as start-on-demand CI build node.
#
MODULES=dep
' | sudo tee "$ROOT/etc/initramfs-tools/conf.d/modules"

fi # if [ "$optimize_for_kvm_vm" == "yes" ]...

echo "#!/bin/bash
set -x
update-grub2
update-initramfs -c -k all
grub-install $(if [ "${optimize_for_kvm_vm}" == "yes" ]; then echo /dev/vda; else echo /dev/sda; fi)
/tmp/off
" | sudo tee "$ROOT/tmp/grub-self-install.sh"
sudo chmod ugo+x "$ROOT/tmp/grub-self-install.sh"
sudo rm -rf "${ROOT}/run/systemd"

if [ -L "${ROOT}/vmlinuz" ]; then
	vmlinuz_link=/vmlinuz
elif [ -L "${ROOT}/boot/vmlinuz" ]; then
	vmlinuz_link=/boot/vmlinuz
else
	vmlinuz_link=/vmlinuz
fi

if [ -L "${ROOT}/initrd.img" ]; then
	initrd_link=/initrd.img
elif [ -L "${ROOT}/boot/initrd.img" ]; then
	initrd_link=/boot/initrd.img
else
	initrd_link=/initrd.img
fi

umount_ROOT

sleep 1

root_img_fmt=$(qemu-img info $1 | grep 'file format' | cut -d ' '  -f 3)
root_dev=$(part_ROOT $1)
vmlinuz="$(guestfish -a "$1" -m $root_dev:/ readlink $vmlinuz_link)"
initrd="$(guestfish -a "$1" -m $root_dev:/ readlink $initrd_link)"

guestfish -a "$1" -m $root_dev:/ copy-out $(dirname $vmlinuz_link)/$vmlinuz $tmp
guestfish -a "$1" -m $root_dev:/ copy-out $(dirname $vmlinuz_link)/$initrd $tmp

rm -f $tmp/vmlinuz $tmp/initrd.img
mv $tmp/$(basename $vmlinuz) $tmp/vmlinuz
mv $tmp/$(basename $initrd) $tmp/initrd.img

if [ "$optimize_for_kvm_vm" == "yes" ]; then
	# If the image is intended to boot only on KVM/QEMU, then use virtio
	# block device (which will likely be used). Otherwise, update-initramfs
	# would pull in SATA modules, making initrd larger and this slowing down
	# boot.

	# TODO: Fix hardcoded /dev/vda1!
	qemu-system-x86_64 \
    	-M q35 -m "512M" \
		-kernel "$tmp/vmlinuz" -initrd "$tmp/initrd.img" -append "root=/dev/vda1 rw console=ttyS0 init=/tmp/grub-self-install.sh" \
		-nographic \
		-drive "file=$1,format=$root_img_fmt,if=virtio" \
		-netdev user,id=hostnet0 -device virtio-net-pci,netdev=hostnet0
else
	# Otherwise, use SATA. Note that virtio_blk module us always included so
	# this image should boot using virtio block device too,
	qemu-system-x86_64 \
    	-M q35 -m "512M" \
		-kernel "$tmp/vmlinuz" -initrd "$tmp/initrd.img" -append "root=$root_dev rw init=/tmp/grub-self-install.sh" \
		-drive if=none,id=disk0,cache=none,aio=native,file=$1,format=$root_img_fmt -device ahci,id=ahci -device ide-hd,drive=disk0,bus=ahci.0 \
		-netdev user,id=hostnet0 -device virtio-net-pci,netdev=hostnet0
fi