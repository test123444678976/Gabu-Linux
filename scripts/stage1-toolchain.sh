#!/usr/bin/env bash
# LFS caps. 5 e 6: toolchain cruzado + ferramentas temporárias. Corre como utilizador "lfs".
if [ "$(id -u)" = 0 ]; then
  L="${LFS:-/lfs}"
  exec sudo -H -u lfs env -i HOME=/home/lfs TERM="${TERM:-dumb}" LFS="$L" LC_ALL=POSIX \
    LFS_TGT=x86_64-lfs-linux-gnu PATH="/usr/bin:$L/tools/bin" CONFIG_SITE="$L/usr/share/config.site" \
    MAKEFLAGS="-j$(nproc)" bash "$0" "$@"
fi
STAGE=s1
source "$(dirname "$(readlink -f "$0")")/lib.sh"

GCCV=$(ver gcc)
GLIBC2=$(ver2 glibc)

gcc_extras() {
  local p
  for p in mpfr gmp mpc; do
    tar -xf "$(tarball "$p-[0-9]*.tar.*")"
    mv "$p"-[0-9]* "$p"
  done
}
# configure/make/install padrão para o sistema alvo (cross)
std_host() {
  local bt; bt=$(sh "$(find . -maxdepth 2 -name config.guess -print -quit)")
  ./configure --prefix=/usr --host="$LFS_TGT" --build="$bt" "$@"
  make; make DESTDIR="$LFS" install
}

# ---------- Capítulo 5 ----------
do_binutils_pass1() {
  mkdir -v build; cd build
  ../configure --prefix="$LFS/tools" --with-sysroot="$LFS" --target="$LFS_TGT" \
    --disable-nls --enable-gprofng=no --disable-werror --enable-new-dtags --enable-default-hash-style=gnu
  make; make install
}
do_gcc_pass1() {
  gcc_extras
  sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
  mkdir -v build; cd build
  ../configure --target="$LFS_TGT" --prefix="$LFS/tools" --with-glibc-version="$GLIBC2" \
    --with-sysroot="$LFS" --with-newlib --without-headers --enable-default-pie --enable-default-ssp \
    --disable-nls --disable-shared --disable-multilib --disable-threads --disable-libatomic \
    --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --disable-libstdcxx \
    --enable-languages=c,c++
  make; make install
  cd ..
  cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
    "$(dirname "$("$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
}
do_linux_headers() {
  make mrproper; make headers
  find usr/include -type f ! -name '*.h' -delete
  cp -rv usr/include "$LFS/usr"
}
do_glibc() {
  ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-linux-x86-64.so.2"
  ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
  patch -Np1 -i "$(patchfile 'glibc-*-fhs-1.patch')"
  mkdir -v build; cd build
  echo "rootsbindir=/usr/sbin" > configparms
  ../configure --prefix=/usr --host="$LFS_TGT" --build="$(../scripts/config.guess)" \
    --disable-nscd libc_cv_slibdir=/usr/lib --enable-kernel=5.4
  make; make DESTDIR="$LFS" install
  sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"
}
do_libstdcxx() {
  mkdir -v build; cd build
  ../libstdc++-v3/configure --host="$LFS_TGT" --build="$(../config.guess)" --prefix=/usr \
    --disable-multilib --disable-nls --disable-libstdcxx-pch \
    --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/$GCCV"
  make; make DESTDIR="$LFS" install
  rm -v "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

log "== Capítulo 5: toolchain cruzado =="
build binutils-pass1 'binutils-[0-9]*.tar.*'
build gcc-pass1      'gcc-[0-9]*.tar.*'
build linux-headers  'linux-[0-9]*.tar.*'
build glibc
build libstdcxx      'gcc-[0-9]*.tar.*'

# ---------- Capítulo 6 ----------
do_m4()       { std_host; }
do_ncurses() {
  sed -i s/mawk// configure
  mkdir build; pushd build
    ../configure AWK=gawk
    make -C include; make -C progs tic
  popd
  ./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)" --mandir=/usr/share/man \
    --with-manpage-format=normal --with-shared --without-normal --with-cxx-shared --without-debug \
    --without-ada --disable-stripping AWK=gawk
  make; make DESTDIR="$LFS" TIC_PATH="$PWD/build/progs/tic" install
  ln -sv libncursesw.so "$LFS/usr/lib/libncurses.so"
  sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
}
do_bash() {
  std_host --without-bash-malloc
  ln -sv bash "$LFS/bin/sh"
}
do_coreutils() {
  std_host --enable-install-program=hostname --enable-no-install-program=kill,uptime
  mv -v "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
  mkdir -pv "$LFS/usr/share/man/man8"
  mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
  sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"
}
do_diffutils() { std_host; }
do_file() {
  mkdir build; pushd build
    ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib
    make
  popd
  ./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)"
  make FILE_COMPILE="$PWD/build/src/file"
  make DESTDIR="$LFS" install
  rm -v "$LFS/usr/lib/libmagic.la"
}
do_findutils() { std_host --localstatedir=/var/lib/locate; }
do_gawk()      { sed -i 's/extras//' Makefile.in; std_host; }
do_grep()      { std_host; }
do_gzip()      { std_host; }
do_make()      { std_host --without-guile; }
do_patch()     { std_host; }
do_sed()       { std_host; }
do_tar()       { std_host; }
do_xz() {
  std_host --disable-static --docdir="/usr/share/doc/xz-$(ver xz)"
  rm -v "$LFS/usr/lib/liblzma.la"
}
do_binutils_pass2() {
  sed '6009s/$add_dir//' -i ltmain.sh
  mkdir -v build; cd build
  ../configure --prefix=/usr --build="$(../config.guess)" --host="$LFS_TGT" --disable-nls \
    --enable-shared --enable-gprofng=no --disable-werror --enable-64-bit-bfd \
    --enable-new-dtags --enable-default-hash-style=gnu
  make; make DESTDIR="$LFS" install
  rm -v "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}
do_gcc_pass2() {
  gcc_extras
  sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
  sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
  mkdir -v build; cd build
  ../configure --build="$(../config.guess)" --host="$LFS_TGT" --target="$LFS_TGT" \
    LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc" --prefix=/usr --with-build-sysroot="$LFS" \
    --enable-default-pie --enable-default-ssp --disable-nls --disable-multilib --disable-libatomic \
    --disable-libgomp --disable-libquadmath --disable-libsanitizer --disable-libssp --disable-libvtv \
    --enable-languages=c,c++
  make; make DESTDIR="$LFS" install
  ln -sv gcc "$LFS/usr/bin/cc"
}

log "== Capítulo 6: ferramentas temporárias =="
for p in m4 ncurses bash coreutils diffutils file findutils gawk grep gzip make patch sed tar xz; do
  build "$p"
done
build binutils-pass2 'binutils-[0-9]*.tar.*'
build gcc-pass2      'gcc-[0-9]*.tar.*'
log "Stage 1 concluído."
