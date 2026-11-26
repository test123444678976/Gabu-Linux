#!/usr/bin/env bash
# LFS cap. 7 (dentro do chroot): estrutura de directórios, ficheiros essenciais e ferramentas finais temporárias
STAGE=s2
source "$(dirname "$(readlink -f "$0")")/lib.sh"

if [ ! -e "$DONE/s2-layout" ]; then
  log "Estrutura de directórios"
  mkdir -pv /{boot,home,mnt,opt,srv} /etc/{opt,sysconfig} /lib/firmware /media/{floppy,cdrom}
  mkdir -pv /usr/{,local/}{include,src} /usr/lib/locale /usr/local/{bin,lib,sbin}
  mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man,misc,terminfo,zoneinfo}
  mkdir -pv /usr/{,local/}share/man/man{1..8}
  mkdir -pv /var/{cache,local,log,mail,opt,spool} /var/lib/{color,misc,locate}
  ln -sfv /run /var/run; ln -sfv /run/lock /var/lock
  install -dv -m 0750 /root; install -dv -m 1777 /tmp /var/tmp

  ln -sfv /proc/self/mounts /etc/mtab
  cat > /etc/hosts <<EOF
127.0.0.1  localhost $GABU_HOSTNAME
::1        localhost
EOF
  cat > /etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF
  cat > /etc/group <<'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF
  touch /var/log/{btmp,lastlog,faillog,wtmp}
  chgrp -v utmp /var/log/lastlog
  chmod -v 664 /var/log/lastlog; chmod -v 600 /var/log/btmp
  touch "$DONE/s2-layout"
fi

PERL_MM=$(ver2 perl)

do_gettext_tmp() { ./configure --disable-shared; make; cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin; }
do_bison_tmp()   { ./configure --prefix=/usr; make; make install; }
do_perl_tmp() {
  sh Configure -des -D prefix=/usr -D vendorprefix=/usr -D useshrplib \
    -D privlib=/usr/lib/perl5/$PERL_MM/core_perl -D archlib=/usr/lib/perl5/$PERL_MM/core_perl \
    -D sitelib=/usr/lib/perl5/$PERL_MM/site_perl -D sitearch=/usr/lib/perl5/$PERL_MM/site_perl \
    -D vendorlib=/usr/lib/perl5/$PERL_MM/vendor_perl -D vendorarch=/usr/lib/perl5/$PERL_MM/vendor_perl
  make; make install
}
do_Python_tmp()  { ./configure --prefix=/usr --enable-shared --without-ensurepip; make; make install; }
do_texinfo_tmp() { ./configure --prefix=/usr; make; make install; }
do_util_linux_tmp() {
  mkdir -pv /var/lib/hwclock
  ./configure --libdir=/usr/lib --runstatedir=/run --disable-chfn-chsh --disable-login --disable-nologin \
    --disable-su --disable-setpriv --disable-runuser --disable-pylibmount --disable-static \
    --disable-liblastlog2 --without-python ADJTIME_PATH=/var/lib/hwclock/adjtime
  make; make install
}

build gettext-tmp    'gettext-[0-9]*.tar.*'
build bison-tmp      'bison-[0-9]*.tar.*'
build perl-tmp       'perl-[0-9]*.tar.*'
build Python-tmp     'Python-[0-9]*.tar.*'
build texinfo-tmp    'texinfo-[0-9]*.tar.*'
build util-linux-tmp 'util-linux-[0-9]*.tar.*'

if [ ! -e "$DONE/s2-cleanup" ]; then
  rm -rf /usr/share/{info,man,doc}/*
  find /usr/{lib,libexec} -name '*.la' -delete
  rm -rf /tools
  touch "$DONE/s2-cleanup"
fi
log "Stage 2 concluído."
