#!/usr/bin/env bash
# Uso: chroot-run.sh <script-em-scripts/> [args...]   (monta sistemas virtuais, corre no chroot, desmonta)
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
source "$(dirname "$(readlink -f "$0")")/../config/gabu.conf"

# Capítulo 7.2: dono root (só na primeira vez, é idempotente)
chown -R root:root "$LFS"/{usr,lib,var,etc,bin,sbin,tools,lib64} 2>/dev/null || true
mkdir -p "$LFS"/{dev,proc,sys,run}

cleanup() { for m in dev/pts dev/shm dev proc sys run; do umount "$LFS/$m" 2>/dev/null || true; done; }
trap cleanup EXIT

mountpoint -q "$LFS/dev"     || mount -v --bind /dev "$LFS/dev"
mountpoint -q "$LFS/dev/pts" || mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
mountpoint -q "$LFS/proc"    || mount -vt proc proc "$LFS/proc"
mountpoint -q "$LFS/sys"     || mount -vt sysfs sysfs "$LFS/sys"
mountpoint -q "$LFS/run"     || mount -vt tmpfs tmpfs "$LFS/run"
if [ -h "$LFS/dev/shm" ]; then install -v -d -m 1777 "$LFS$(realpath /dev/shm)"
else mountpoint -q "$LFS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"; fi

script=$1; shift
chroot "$LFS" /usr/bin/env -i HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
  IN_CHROOT=1 MAKEFLAGS="-j$(nproc)" /bin/bash "/gabu/scripts/$script" "$@"
