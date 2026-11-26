#!/usr/bin/env bash
# Uso (dentro do chroot): stage5-packages.sh <secção> ...
# Compila os pacotes de uma secção do packages.manifest (fontes já descarregadas por fetch-extra.sh).
STAGE=s5
source "$(dirname "$(readlink -f "$0")")/lib.sh"
MANIFEST="$GABU_ROOT_DIR/config/packages.manifest"
ARGS=""

# ---------- receitas genéricas ----------
gen_auto() {
  [ -x configure ] || { if [ -x autogen.sh ]; then NOCONFIGURE=1 ./autogen.sh; else autoreconf -fi; fi; }
  local H o=() a n
  H=$(./configure --help)
  for a in $ARGS; do
    case $a in
      \?*) a=${a#\?}; n=${a%%=*}; grep -q -- "$n" <<<"$H" && o+=("$a") ;;
      *)   o+=("$a") ;;
    esac
  done
  for a in --disable-static --disable-gtk-doc --disable-introspection --disable-docs --disable-vala --disable-gir; do
    grep -q -- "$a" <<<"$H" && o+=("$a")
  done
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var "${o[@]}"
  make; make install
}
gen_meson() {
  mkdir -p bld; cd bld
  local o; mapfile -t o < <(MESON_SRC=.. mopts $ARGS)
  meson setup .. --prefix=/usr --buildtype=release --libdir=lib --sysconfdir=/etc --localstatedir=/var \
    --wrap-mode=nofallback "${o[@]}"
  ninja; ninja install
}
gen_cmake() {
  # shellcheck disable=SC2086
  cmake -S . -B bld -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib -Wno-dev $ARGS
  cmake --build bld; cmake --install bld
}

# ---------- receitas específicas ----------
do_cmake() {
  ./bootstrap --prefix=/usr --parallel="$(nproc)" --no-qt-gui -- -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF -DCMAKE_USE_OPENSSL=ON
  make; make install
}
do_xxhash()   { make PREFIX=/usr; make PREFIX=/usr install; rm -f /usr/lib/libxxhash.a; }
do_triehash() { install -Dm755 triehash.pl /usr/bin/triehash; }
do_dpkg() {
  # --build/--host sem vendor para o dpkg reconhecer a arquitectura amd64
  ./configure --build=x86_64-linux-gnu --host=x86_64-linux-gnu --prefix=/usr --sysconfdir=/etc \
    --localstatedir=/var --disable-dselect --disable-devel-docs --without-libselinux
  make; make install
  mkdir -p /var/lib/dpkg/{info,updates,alternatives} /etc/dpkg/dpkg.cfg.d /var/log
  touch /var/lib/dpkg/{status,available}
  [ "$(dpkg --print-architecture)" = amd64 ] || { echo "dpkg não reconhece amd64"; exit 1; }
}
do_apt() {
  cmake -S . -B bld -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_SYSCONFDIR=/etc -DCMAKE_INSTALL_LOCALSTATEDIR=/var \
    -DWITH_DOC=OFF -DWITH_TESTS=OFF -DBUILD_TESTING=OFF -Wno-dev
  cmake --build bld; cmake --install bld
  mkdir -p /etc/apt/{apt.conf.d,sources.list.d,preferences.d,trusted.gpg.d} \
           /var/lib/apt/lists/partial /var/cache/apt/archives/partial /var/log/apt
  id _apt &>/dev/null || useradd -r -u 42 -g nogroup -d /nonexistent -s /usr/bin/false _apt
  ldconfig
}
do_rust() {
  ./install.sh --prefix=/usr --components=rustc,cargo,rust-std-x86_64-unknown-linux-gnu --disable-ldconfig
}
do_dejavu_fonts() { install -Dm644 ttf/*.ttf -t /usr/share/fonts/truetype/dejavu; }

# ---------- pós-instalação por secção ----------
post_apt() {
  cat > /etc/apt/sources.list <<'EOF'
# Repositório oficial do Gabu Linux: ainda por publicar.
# deb https://exemplo.invalido/gabu stable main
EOF
  cat > /etc/apt/sources.list.d/gabu-local.list <<'EOF'
deb [trusted=yes] file:/var/lib/gabu/repo ./
EOF
  mkdir -p /var/lib/gabu/repo
}
post_gfx() {
  ldconfig
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
  gdk-pixbuf-query-loaders --update-cache || true
  gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
  update-mime-database /usr/share/mime || true
  fc-cache -f || true
}
post_xserver() {
  ldconfig
  mkdir -p /etc/X11 /var/lib/xkb
  printf 'needs_root_rights=yes\nallowed_users=anybody\n' > /etc/X11/Xwrapper.config
  find /usr -name Xorg.wrap -exec chmod u+s {} \; || true
  fc-cache -f || true
}
post_mate() {
  ldconfig
  glib-compile-schemas /usr/share/glib-2.0/schemas || true
  gdk-pixbuf-query-loaders --update-cache || true
  for d in /usr/share/icons/*/; do gtk-update-icon-cache -qtf "$d" || true; done
  update-desktop-database /usr/share/applications || true
  update-mime-database /usr/share/mime || true

  # Sessão: autologin em tty1 -> startx -> mate-session (sem PAM/display manager nesta fase)
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $GABU_USER %I \$TERM
EOF
  local h=/home/$GABU_USER
  echo 'exec mate-session' > $h/.xinitrc
  cat > $h/.bash_profile <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then exec startx -- -nolisten tcp vt1; fi
EOF
  chown "$GABU_USER:$GABU_USER" $h/.xinitrc $h/.bash_profile
}

# ---------- execução ----------
run_section() {
  local sec=$1 cur="" line name spec bs fn
  while IFS= read -r line; do
    case $line in ''|\#*) continue ;; \[*\]) cur=${line//[\[\]]/}; continue ;; esac
    [ "$cur" = "$sec" ] || continue
    IFS=';' read -r name spec bs ARGS <<<"$line"
    case $bs in
      custom:*) fn="do_${bs#custom:}" ;;
      auto)  fn=gen_auto ;;
      meson) fn=gen_meson ;;
      cmake) fn=gen_cmake ;;
      *) die "build desconhecido: $bs" ;;
    esac
    build "$name" "$name-[0-9]*.tar.*" "$fn"
  done < "$MANIFEST" 
  ldconfig
  if declare -F "post_${sec//-/_}" >/dev/null; then log "pós-instalação: $sec"; "post_${sec//-/_}"; fi
}

[ $# -gt 0 ] || die "indica a(s) secção(ões)"
for s in "$@"; do log "== Secção: $s =="; run_section "$s"; done
log "Stage 5 concluído: $*"
