#!/usr/bin/env bash
# Utilitário para o GitHub Actions: ci.sh free-space | sync | restore <tar> | save <tar> | chroot <stage> [args]
set -euo pipefail
LFS=${LFS:-/lfs}
cd "$(dirname "$(readlink -f "$0")")/.."

case "${1:?}" in
  free-space)
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL \
                /usr/local/share/powershell /usr/share/swift
    sudo docker image prune -af >/dev/null 2>&1 || true
    df -h /
    ;;
  sync)   # copia o repositório para dentro do LFS (visível no chroot em /gabu)
    sudo mkdir -p "$LFS/gabu"
    sudo rsync -a --delete --exclude .git --exclude out ./ "$LFS/gabu/"
    sudo chmod -R a+rX "$LFS/gabu"
    ;;
  restore)
    sudo mkdir -p "$LFS"
    sudo tar --zstd -xpf "$2" --numeric-owner --xattrs -C /
    ;;
  save)
    for m in dev/pts dev/shm dev proc sys run; do sudo umount "$LFS/$m" 2>/dev/null || true; done
    sudo tar -I 'zstd -T0 -3' --numeric-owner --xattrs -cpf "$2" -C / --exclude='lfs/build' "${LFS#/}"
    sudo chmod a+r "$2"; ls -lh "$2"
    ;;
  chroot) shift; sudo -E bash scripts/chroot-run.sh "$@" ;;
  logs)   sudo chmod -R a+rX "$LFS/.gabu/logs" 2>/dev/null || true ;;
  *) echo "uso: $0 free-space|sync|restore|save|chroot|logs"; exit 1 ;;
esac
