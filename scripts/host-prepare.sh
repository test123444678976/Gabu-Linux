#!/usr/bin/env bash
# Prepara o host (Ubuntu) para construir o LFS. Correr como root.
set -euo pipefail
cd "$(dirname "$0")/.."
source config/gabu.conf
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y --no-install-recommends \
  build-essential bison gawk texinfo m4 patch perl python3 xz-utils zstd bzip2 \
  curl wget ca-certificates rsync file util-linux e2fsprogs \
  qemu-system-x86 qemu-utils socat imagemagick dpkg-dev apt-utils

# Requisitos do LFS: /bin/sh = bash, awk = gawk, yacc = bison -y
ln -sf bash /bin/sh
ln -sf /usr/bin/gawk /usr/bin/awk
printf '#!/bin/sh\nexec bison -y "$@"\n' > /usr/local/bin/yacc
chmod +x /usr/local/bin/yacc

# Layout inicial (capítulo 4 do livro)
mkdir -pv "$LFS"/{etc,var,usr/{bin,lib,sbin},lib64,tools,sources,build,.gabu,dev,proc,sys,run,tmp}
for i in bin lib sbin; do ln -sfnv "usr/$i" "$LFS/$i"; done
id lfs &>/dev/null || useradd -m -s /bin/bash lfs
chown lfs "$LFS"/{usr,usr/*,lib,var,etc,bin,sbin,tools,lib64,sources,build,.gabu}
chmod 1777 "$LFS/tmp"
echo "host pronto, LFS=$LFS"
