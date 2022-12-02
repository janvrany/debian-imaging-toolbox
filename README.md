# Debian and Ubuntu building toolbox

A set of reusable scripts to help building Debian (and Ubuntu) images using
[mmdebstrap][1].

Over years, I wrote a number of scripts to build various Debian images
for various purposes ([riscv-debian][2], [debian-for-toys][3] to name some).
I usually copied older scripts and then modified them for new purpose
and later back-hacked changes. This soon run out of hand.

Recently (late summer 2022) I needed to build another custom Debian
images, yet again. Instead of repeating the same copy-paste-hack
approach to make things even worse, I decided to try and distill out
what's common and reuse this common base. This is what came out.

## !!! BIG FAT WARNING !!!

Scripts in this repository do use `sudo` quite a lot. **IF THERE'S A BUG,
IT MAY WIPE OUT YOUR SYSTEM**. **DO NOT RUN THESE SCRIPTS WITHOUT READING
THEM CAREFULLY FIRST**.

I tried to make do without `sudo`, couple times actually, but always failed
and given up. Maybe I'll try again, until then: *check scripts or hope
for the best!*

## Scripts

 * `./build.sh <root image>`

   Installs bootable Debian system into given *root image* (see section
   *Root image* below on root images). This also executes all customization
   hooks located in `build-hooks` directory located next to `./build.sh`
   script.

 * `grub2.sh <root image>`

   Installs a GRUB2 into the image, making it bootable. This assumes the
   root image is partitioned, uses old (non-GPT) partition table and x86_64
   architecture.

 * `run-shell.sh <root image>`

   Runs a shell within the image using [systemd-nspawn][6]

 * `run-container.sh <root image>`

   Boots up the image as a container using [systemd-nspawn][6].

 * `run-vm.sh <root image>`

   Boots up the image as a virtual machine using QEMU.

## Root image

Scripts in this repository takes *root image* as their first parameter.
The root image might be:

 * A directory. In this case the entire debian system is installed
   into that directory, effectively creating a Debian chroot.

 * A block device containing a ext4 filesystem.

 * A local file containing a disk image in any format supported by
   [libguestfs][4] (including raw images).

   To create a non-partitioned raw ext4 disk image:

   ```sh
   truncate -s 10G root.img
   /sbin/mkfs.ext4 root.img
   ```

   To create partitioned `.qcow2` disk image:

   ```sh
   qemu-img create -f qcow2 root.qcow2 10g
   guestfish -a root.img run : part-disk /dev/sda mbr : part-set-bootable /dev/sda 1 true : mkfs ext4 /dev/sda1
   ```

 * An URL pointing to remote disk image - see section
   [Adding remote storage][5].

   This works in theory, but it is painfully slow.

## Bootstrapping Ubuntu

These scripts also allow to create Ubuntu images, though all defaults are set
for Debian. To boostrap Ubuntu image, use following configuration (in `config.sh`):

    CONFIG_DEBIAN_RELEASE=focal
    CONFIG_DEBIAN_SOURCES="deb http://archive.ubuntu.com/ubuntu $CONFIG_DEBIAN_RELEASE main universe"

## Bootstrapping Ubuntu 22.04 (Jammy Jellyfish) and newer

Bootstraping recent Ubuntu (that is, newer than 20.04) requires additional trick
since Debian's `dpkg` does not suport zstd compression (and will not anytime soon).

To workaround this limitation, the trick is to start building with older version (20.04 Focal Fossa) and then upgrade to Jammy as soon as possible. To do so, just create hook
`build-hooks/customize00-0upgrade-to-jammy.sh` with following contents:

    #!/bin/bash
    source "$(dirname $0)/../functions.sh"
    config "$(dirname $0)/../config.sh" || error "Cannot read config.sh: $1"
    config "$(dirname $0)/../config-local.sh"
    ensure_ROOT $1

    #
    # Config variables
    #
    # None

    sudo sed -i -e 's/focal/jammy/g' "${ROOT}/etc/apt/sources.list"

    chroot "${ROOT}" /usr/bin/apt update
    chroot "${ROOT}" /usr/bin/apt-get -y upgrade
    chroot "${ROOT}" /usr/bin/apt -y upgrade
    chroot "${ROOT}" /usr/bin/apt -y autoremove


## Useful links

 * https://github.com/Kicksecure/security-misc/blob/master/etc/default/grub.d/40_kernel_hardening.cfg

 * https://iceburn.medium.com/how-handle-htpasswd-in-nginx-d6ca28def2e4

 * https://www.root.cz/clanky/sandboxing-se-systemd-zesileni-ochrany-sluzeb-pomoci-namespaces/

 * https://gist.github.com/ageis/f5595e59b1cddb1513d1b425a323db04

 * https://docs.arbitrary.ch/security/systemd.html


[1]: https://gitlab.mister-muffin.de/josch/mmdebstrap
[2]: https://github.com/janvrany/riscv-debian
[3]: https://github.com/janvrany/debian-for-toys
[4]: https://libguestfs.org/
[5]: https://libguestfs.org/guestfish.1.html#adding-remote-storage
[6]: https://www.freedesktop.org/software/systemd/man/systemd-nspawn.html