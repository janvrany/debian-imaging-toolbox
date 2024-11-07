#!/bin/bash
#
# Boot the system im QEMU
#
source "$(dirname $(realpath ${BASH_SOURCE[0]}))/functions.sh"
config "$(dirname $0)/config.sh" || error "Cannot read config.sh: $1"
config "$(dirname $0)/config-local.sh"

#
# Config variables
#
: ${CONFIG_VM_MEM:=512M}
: ${CONFIG_SSHD_PORT:=22}
#
# Boot the system
#
if [ -z "$1" ]; then
    echo "usage: $(basename $0) <ROOT>"
    exit 1
elif [ -d "$1" ]; then
	error "Invalid root filesystem image (must not be directory): $1"
	exit 2
fi

echo "To (SSH) connect to running system, do"
echo
echo "    ssh localhost -p 5522"
echo
if ! confirm "Continue"; then
    exit 0
fi

#
# Check the VM architecture:
#
typeset part=$(part_ROOT $1)
typeset arch=$(guestfish -a $1 run : mount $part / : file-architecture /bin/mount)
typeset qemu=qemu-system-$arch
typeset qemu_opts=
typeset qemu_img_fmt=$(qemu-img info $1 | grep 'file format' | cut -d ' '  -f 3)

case "$arch" in
	x86_64 )
		qemu_opts="-M q35 -accel kvm -nographic"
		;;
	* )
		error "Architecture not yet supported: $arch"
esac

$qemu $qemu_opts \
    -m "$CONFIG_VM_MEM" \
	-drive if=none,id=drive0,cache=none,aio=native,file=$1,format=$qemu_img_fmt -device virtio-blk-pci,drive=drive0 \
	-netdev user,id=hostnet0,hostfwd=tcp::5522-:${CONFIG_SSHD_PORT},hostfwd=tcp::5580-:80 -device virtio-net-pci,netdev=hostnet0 