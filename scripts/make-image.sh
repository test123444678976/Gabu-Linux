#!/usr/bin/env bash
# Uso: make-image.sh <core|desktop>   (como root, no host, com o $LFS restaurado)
# Produz out/gabu-<variante>-<versão>.img (raw, MBR + ext4 + GRUB BIOS) e .qcow2 comprimido.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
cd "$(dirname "$(readlink -f "$0")")/.."
source config/gabu.conf
variant=${1:?core|desktop}
size=6G; [ "$variant" = desktop ] && size=16G
mkdir -p out
img="out/gabu-$variant-$GABU_VERSION.img"
rm -f "$img"; truncate -s "$size" "$img"

printf 'label: dos\nlabel-id: 0x%s\n,,L,*\n' "$GABU_DISK_ID" | sfdisk "$img"
loop=$(losetup -Pf --show "$img")
m=$(mktemp -d)
cleanup() {
  for x in dev/pts dev proc sys; do umount "$m/$x" 2>/dev/null || true; done
  umount "$m" 2>/dev/null || true
  losetup -d "$loop" 2>/dev/null || true
}
trap cleanup EXIT

mkfs.ext4 -F -L gabu-root "${loop}p1"
mount "${loop}p1" "$m"
rsync -aHAX --numeric-ids \
  --exclude=/sources --exclude=/build --exclude=/.gabu --exclude=/gabu --exclude=/tools \
  --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' \
  "$LFS"/ "$m"/
mkdir -p "$m"/{dev,proc,sys,run,tmp}; chmod 1777 "$m/tmp"

# Repositório apt local de demonstração/teste (flat repo, ficheiro://)
work=$(mktemp -d)
mkdir -p "$work/pkg/DEBIAN" "$work/pkg/usr/bin" "$work/repo"
cat > "$work/pkg/DEBIAN/control" <<EOF
Package: gabu-hello
Version: 1.0
Architecture: amd64
Maintainer: Gabu Linux <gabu@localhost>
Description: Pacote de teste do apt no Gabu Linux
EOF
printf '#!/bin/sh\necho "Olá do Gabu Linux!"\n' > "$work/pkg/usr/bin/gabu-hello"
chmod 755 "$work/pkg/usr/bin/gabu-hello"
dpkg-deb --build --root-owner-group "$work/pkg" "$work/repo/gabu-hello_1.0_amd64.deb"
( cd "$work/repo"
  dpkg-scanpackages . /dev/null > Packages
  gzip -k Packages
  apt-ftparchive release . > Release )
mkdir -p "$m/var/lib/gabu/repo"; cp "$work"/repo/* "$m/var/lib/gabu/repo/"
rm -rf "$work"

# GRUB (BIOS) dentro do chroot
mount --bind /dev "$m/dev"; mount -t devpts devpts "$m/dev/pts"
mount -t proc proc "$m/proc"; mount -t sysfs sysfs "$m/sys"
chroot "$m" /usr/sbin/grub-install --target=i386-pc --boot-directory=/boot \
  --modules="part_msdos ext2" "$loop"
cat > "$m/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3
menuentry "$GABU_NAME $GABU_VERSION" {
  insmod part_msdos
  insmod ext2
  search --no-floppy --label gabu-root --set=root
  linux /boot/vmlinuz-gabu root=PARTUUID=${GABU_DISK_ID}-01 ro console=tty0 console=ttyS0,115200
}
EOF
sync
cleanup; trap - EXIT

qemu-img convert -O qcow2 -c "$img" "${img%.img}.qcow2"
echo "Imagem: $img  e  ${img%.img}.qcow2"
