#!/usr/bin/env bash
# LFS cap. 8 (dentro do chroot): sistema final. Sem suites de testes (CI), logo sem tcl/expect/dejagnu.
STAGE=s3
source "$(dirname "$(readlink -f "$0")")/lib.sh"

PERL_MM=$(ver2 perl)
std() { ./configure --prefix=/usr "$@"; make; make install; }

do_man_pages() { rm -v man3/crypt* || true; make -R GIT=false prefix=/usr install; }
do_iana_etc()  { cp -v services protocols /etc; }

do_glibc() {
  patch -Np1 -i "$(patchfile 'glibc-*-fhs-1.patch')"
  mkdir -v build; cd build
  echo "rootsbindir=/usr/sbin" > configparms
  ../configure --prefix=/usr --disable-werror --disable-nscd libc_cv_slibdir=/usr/lib \
    --enable-stack-protector=strong --enable-kernel=5.4
  make
  touch /etc/ld.so.conf
  sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
  make install
  sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

  localedef -i C -f UTF-8 C.UTF-8
  localedef -i en_US -f UTF-8 en_US.UTF-8
  localedef -i pt_PT -f UTF-8 pt_PT.UTF-8

  cat > /etc/nsswitch.conf <<'EOF'
passwd: files systemd
group: files systemd
shadow: files systemd
hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
EOF
  # tzdata
  mkdir -p ../tz; tar -xf "$(tarball 'tzdata*.tar.*')" -C ../tz
  local ZONEINFO=/usr/share/zoneinfo tz
  mkdir -pv $ZONEINFO/{posix,right}
  ( cd ../tz
    for tz in etcetera southamerica northamerica europe africa antarctica asia australasia backward; do
      zic -L /dev/null -d $ZONEINFO "$tz"
      zic -L /dev/null -d $ZONEINFO/posix "$tz"
      zic -L leapseconds -d $ZONEINFO/right "$tz"
    done
    cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
    zic -d $ZONEINFO -p America/New_York )
  ln -sfv "/usr/share/zoneinfo/$GABU_TZ" /etc/localtime

  cat > /etc/ld.so.conf <<'EOF'
include /etc/ld.so.conf.d/*.conf
/usr/local/lib
/opt/lib
EOF
  mkdir -pv /etc/ld.so.conf.d
}

do_zlib() { std; rm -fv /usr/lib/libz.a; }
do_bzip2() {
  patch -Np1 -i "$(patchfile 'bzip2-*-install_docs-1.patch')"
  sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
  sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
  make -f Makefile-libbz2_so; make clean; make
  make PREFIX=/usr install
  cp -av libbz2.so.* /usr/lib
  ln -sfv "$(basename "$(ls libbz2.so.1.0.[0-9]* | head -n1)")" /usr/lib/libbz2.so
  cp -v bzip2-shared /usr/bin/bzip2
  for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 $i; done
  rm -fv /usr/lib/libbz2.a
}
do_xz()   { std --disable-static; }
do_lz4()  { make BUILD_STATIC=no PREFIX=/usr; make BUILD_STATIC=no PREFIX=/usr install; }
do_zstd() { make prefix=/usr; make prefix=/usr install; rm -v /usr/lib/libzstd.a; }
do_file() { std; }
do_readline() {
  sed -i '/MV.*old/d' Makefile.in
  sed -i '/{OLDSUFF}/c:' support/shlib-install
  sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
  ./configure --prefix=/usr --disable-static --with-curses
  make SHLIB_LIBS="-lncursesw"; make install
}
do_pcre2() {
  std --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 --enable-pcre2grep-libz \
    --enable-pcre2grep-libbz2 --enable-pcre2test-libreadline --disable-static
}
do_m4() { std; }
do_bc() { CC=gcc ./configure --prefix=/usr -G -O3 -r; make; make install; }
do_flex() {
  std --disable-static
  ln -sv flex /usr/bin/lex; ln -sv flex.1 /usr/share/man/man1/lex.1
}
do_pkgconf() {
  std --disable-static
  ln -sv pkgconf /usr/bin/pkg-config; ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
}
do_binutils() {
  mkdir -v build; cd build
  ../configure --prefix=/usr --sysconfdir=/etc --enable-ld=default --enable-plugins --enable-shared \
    --disable-werror --enable-64-bit-bfd --enable-new-dtags --with-system-zlib --enable-default-hash-style=gnu
  make tooldir=/usr; make tooldir=/usr install
  rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a /usr/share/doc/gprofng/
}
do_gmp()   { std --enable-cxx --disable-static; }
do_mpfr()  { std --disable-static --enable-thread-safe; }
do_mpc()   { std --disable-static; }
do_attr()  { std --disable-static --sysconfdir=/etc; }
do_acl()   { std --disable-static; }
do_libcap() {
  sed -i '/install -m.*STA/d' libcap/Makefile
  make prefix=/usr lib=lib; make prefix=/usr lib=lib install
}
do_libxcrypt() { std --enable-hashes=strong,glibc --enable-obsolete-api=no --disable-static --disable-failure-tokens; }
do_shadow() {
  sed -i 's/groups$(EXEEXT) //' src/Makefile.in
  find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
  find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
  find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;
  sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' -e 's:/var/spool/mail:/var/mail:' \
      -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' -i etc/login.defs
  touch /usr/bin/passwd
  ./configure --sysconfdir=/etc --disable-static --with-{b,yes}crypt --without-libbsd --with-group-name-max-length=32
  make; make exec_prefix=/usr install; make -C man install-man
  pwconv; grpconv
  mkdir -p /etc/default; useradd -D --gid 999
  sed -i '/MAIL/s/yes/no/' /etc/default/useradd
}
do_gcc() {
  local GCCV; GCCV=$(ver gcc)
  sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
  mkdir -v build; cd build
  ../configure --prefix=/usr LD=ld --enable-languages=c,c++ --enable-default-pie --enable-default-ssp \
    --enable-host-pie --disable-multilib --disable-bootstrap --disable-fixincludes --with-system-zlib
  make; make install
  chown -v -R root:root /usr/lib/gcc/"$(gcc -dumpmachine)"/"$GCCV"/include{,-fixed}
  ln -svr /usr/bin/cpp /usr/lib
  ln -sv gcc.1 /usr/share/man/man1/cc.1
  mkdir -pv /usr/lib/bfd-plugins
  ln -sfv ../../libexec/gcc/"$(gcc -dumpmachine)"/"$GCCV"/liblto_plugin.so /usr/lib/bfd-plugins/
  mkdir -pv /usr/share/gdb/auto-load/usr/lib
  mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib || true
  # teste de sanidade do toolchain
  echo 'int main(){}' > /tmp/dummy.c
  cc /tmp/dummy.c -o /tmp/a.out
  readelf -l /tmp/a.out | grep -q 'ld-linux-x86-64.so.2'
  rm -f /tmp/dummy.c /tmp/a.out
}
do_ncurses() {
  local lib
  ./configure --prefix=/usr --mandir=/usr/share/man --with-shared --without-debug --without-normal \
    --with-cxx-shared --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig
  make; make DESTDIR="$PWD/dest" install
  install -vm755 "$(ls dest/usr/lib/libncursesw.so.*.* | head -n1)" /usr/lib
  rm -v "$(ls dest/usr/lib/libncursesw.so.*.* | head -n1)"
  sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
  cp -av dest/* /
  for lib in ncurses form panel menu; do
    ln -sfv ${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc /usr/lib/pkgconfig/${lib}.pc
  done
  ln -sfv libncursesw.so /usr/lib/libcurses.so
}
do_sed()     { std; }
do_psmisc()  { std; }
do_gettext() { std --disable-static; chmod -v 0755 /usr/lib/preloadable_libintl.so; }
do_bison()   { std; }
do_grep()    { sed -i "s/echo/#echo/" src/egrep.sh || true; std; }
do_bash()    { std --without-bash-malloc --with-installed-readline; }
do_libtool() { std; rm -fv /usr/lib/libltdl.a; }
do_gdbm()    { std --disable-static --enable-libgdbm-compat; }
do_gperf()   { std; }
do_expat()   { std --disable-static; }
do_inetutils() {
  sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
  std --bindir=/usr/bin --localstatedir=/var --disable-logger --disable-whois --disable-rcp \
      --disable-rexec --disable-rlogin --disable-rsh --disable-servers
  mv -v /usr/{,s}bin/ifconfig
}
do_less() { std --sysconfdir=/etc; }
do_perl() {
  export BUILD_ZLIB=False BUILD_BZIP2=0
  sh Configure -des -D prefix=/usr -D vendorprefix=/usr \
    -D privlib=/usr/lib/perl5/$PERL_MM/core_perl -D archlib=/usr/lib/perl5/$PERL_MM/core_perl \
    -D sitelib=/usr/lib/perl5/$PERL_MM/site_perl -D sitearch=/usr/lib/perl5/$PERL_MM/site_perl \
    -D vendorlib=/usr/lib/perl5/$PERL_MM/vendor_perl -D vendorarch=/usr/lib/perl5/$PERL_MM/vendor_perl \
    -D man1dir=/usr/share/man/man1 -D man3dir=/usr/share/man/man3 -D pager="/usr/bin/less -isR" \
    -D useshrplib -D usethreads
  make; make install
}
do_XML_Parser() { perl Makefile.PL; make; make install; }
do_intltool() {
  sed -i 's:\\\${:\\\$\\{:' intltool-update.in
  std
}
do_autoconf() { std; }
do_automake() { std; }
do_openssl() {
  ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
  make
  sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
  make MANSUFFIX=ssl install
}
do_elfutils() {
  ./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
  make; make -C libelf install
  install -vm644 config/libelf.pc /usr/lib/pkgconfig
  rm /usr/lib/libelf.a
}
do_libffi() { std --disable-static --with-gcc-arch=x86-64; }   # NUNCA native: a imagem corre noutras CPUs
do_sqlite() {
  ./configure --prefix=/usr --disable-static --enable-fts{4,5} \
    CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 -D SQLITE_ENABLE_UNLOCK_NOTIFY=1 -D SQLITE_ENABLE_DBSTAT_VTAB=1 -D SQLITE_SECURE_DELETE=1"
  make; make install
}
do_Python() {
  ./configure --prefix=/usr --enable-shared --with-system-expat
  make; make install
  cat > /etc/pip.conf <<'EOF'
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
}
do_flit_core()  { pyinst flit_core; }
do_packaging()  { pyinst packaging; }
do_wheel()      { pyinst wheel; }
do_setuptools() { pyinst setuptools; }
do_ninja()      { python3 configure.py --bootstrap; install -vm755 ninja /usr/bin/; }
do_meson() {
  pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
  pip3 install --no-index --find-links dist meson
}
do_kmod() {
  if [ -f configure ]; then
    std --sysconfdir=/etc --with-openssl --with-xz --with-zstd --with-zlib --disable-manpages
  else
    mkdir -p build; cd build
    mapfile -t o < <(mopts -Dmanpages=false)
    meson setup .. --prefix=/usr --buildtype=release --libdir=lib "${o[@]}"
    ninja; ninja install
  fi
  for t in depmod insmod modinfo modprobe rmmod; do ln -sfv ../bin/kmod /usr/sbin/$t; done
  ln -sfv kmod /usr/bin/lsmod
}
do_coreutils() {
  local p; p=$(patchfile 'coreutils-*-i18n-*.patch')
  if [ -n "$p" ]; then patch -Np1 -i "$p"; autoreconf -fv; automake -af; fi
  FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --enable-no-install-program=kill,uptime
  make; make install
  mv -v /usr/bin/chroot /usr/sbin
  mkdir -p /usr/share/man/man8
  mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
  sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
}
do_diffutils() { std; }
do_gawk() {
  sed -i 's/extras//' Makefile.in
  ./configure --prefix=/usr; make
  rm -f /usr/bin/gawk-[0-9]*
  make install
  ln -sv gawk.1 /usr/share/man/man1/awk.1
}
do_findutils() { std --localstatedir=/var/lib/locate; }
do_groff()     { PAGE=A4 ./configure --prefix=/usr; make; make install; }
do_grub() {
  unset {C,CPP,CXX,LD}FLAGS
  std --sysconfdir=/etc --disable-efiemu --disable-werror
  mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions 2>/dev/null || true
}
do_gzip() { std; }
do_iproute2() {
  sed -i /ARPD/d Makefile; rm -fv man/man8/arpd.8
  make NETNS_RUN_DIR=/run/netns; make SBINDIR=/usr/sbin install
}
do_kbd() {
  local p; p=$(patchfile 'kbd-*-backspace-1.patch'); [ -z "$p" ] || patch -Np1 -i "$p"
  sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
  sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
  std --disable-vlock
}
do_libpipeline() { std; }
do_make()  { std; }
do_patch() { std; }
do_tar()   { FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr; make; make install; }
do_texinfo() { std; }
do_vim() {
  echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
  std
  ln -sv vim /usr/bin/vi
}
do_MarkupSafe() { pyinst MarkupSafe; }
do_jinja2()     { pyinst Jinja2; }
do_systemd() {
  sed -e 's/GROUP="render"/GROUP="video"/' -e 's/GROUP="sgx", //' -i rules.d/50-udev-default.rules.in
  mkdir -p build; cd build
  mapfile -t o < <(mopts -Ddefault-dnssec=no -Dfirstboot=false -Dinstall-tests=false -Dldconfig=false \
    -Dsysusers=false -Drpmmacrosdir=no -Dhomed=disabled -Duserdb=false -Dman=disabled -Dmode=release \
    -Dpamconfdir=no -Ddev-kvm-mode=0660 -Dnobody-group=nogroup -Dsysupdate=disabled -Dukify=disabled)
  meson setup .. --prefix=/usr --buildtype=release --libdir=lib "${o[@]}"
  ninja; ninja install
  mkdir -p /etc/machine-id.d; rmdir /etc/machine-id.d
  : > /etc/machine-id
  systemctl preset-all || true
}
do_dbus() {
  mkdir build; cd build
  meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback --libdir=lib ..
  ninja; ninja install
  mkdir -p /var/lib/dbus
  ln -sfv /etc/machine-id /var/lib/dbus
}
do_man_db() { std --sysconfdir=/etc --disable-setuid --enable-cache-owner=bin; }
do_procps_ng() { std --disable-static --disable-kill --enable-watch8bit --with-systemd; }
do_util_linux() {
  mkdir -pv /var/lib/hwclock
  ./configure --bindir=/usr/bin --libdir=/usr/lib --runstatedir=/run --sbindir=/usr/sbin \
    --disable-chfn-chsh --disable-login --disable-nologin --disable-su --disable-setpriv \
    --disable-runuser --disable-pylibmount --disable-liblastlog2 --disable-static --without-python \
    ADJTIME_PATH=/var/lib/hwclock/adjtime
  make; make install
}
do_e2fsprogs() {
  mkdir -v build; cd build
  ../configure --prefix=/usr --sysconfdir=/etc --enable-elf-shlibs --disable-libblkid \
    --disable-libuuid --disable-uuidd --disable-fsck
  make; make install
  rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
}

# Ordem do capítulo 8 (nome ; glob opcional do tarball)
while IFS=';' read -r n pat; do
  [ -n "$n" ] || continue
  build "$n" "$pat"
done <<'EOF'
man-pages;man-pages-[0-9]*.tar.*
iana-etc
glibc
zlib
bzip2
xz
lz4
zstd
file
readline
pcre2
m4
bc
flex
pkgconf
binutils
gmp
mpfr
mpc
attr
acl
libcap
libxcrypt
shadow
gcc
ncurses
sed
psmisc
gettext
bison
grep
bash
libtool
gdbm
gperf
expat
inetutils
less
perl
XML-Parser
intltool
autoconf
automake
openssl
elfutils
libffi
sqlite;sqlite-autoconf-*.tar.*
Python
flit_core
packaging
wheel
setuptools
ninja
meson
kmod
coreutils
diffutils
gawk
findutils
groff
grub
gzip
iproute2
kbd
libpipeline
make
patch
tar
texinfo
vim
MarkupSafe
jinja2
systemd
dbus
man-db
procps-ng
util-linux
e2fsprogs
EOF
ldconfig
log "Stage 3 concluído."
