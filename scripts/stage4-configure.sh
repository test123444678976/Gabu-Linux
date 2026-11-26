#!/usr/bin/env bash
# LFS caps. 9 e 10 (dentro do chroot): configuração do sistema, identidade Gabu, utilizadores e kernel
STAGE=s4
source "$(dirname "$(readlink -f "$0")")/lib.sh"

configure_system() {
  echo "$GABU_HOSTNAME" > /etc/hostname
  mkdir -p /etc/systemd/network
  cat > /etc/systemd/network/10-dhcp.network <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=ipv4
EOF
  ln -sfv /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  echo "LANG=$GABU_LOCALE" > /etc/locale.conf
  printf 'KEYMAP=%s\n' "$GABU_KEYMAP" > /etc/vconsole.conf
  cat > /etc/os-release <<EOF
NAME="$GABU_NAME"
VERSION="$GABU_VERSION"
ID=gabu
ID_LIKE=lfs
PRETTY_NAME="$GABU_NAME $GABU_VERSION"
VERSION_ID="$GABU_VERSION"
HOME_URL="https://github.com/"
EOF
  cat > /etc/lsb-release <<EOF
DISTRIB_ID="$GABU_NAME"
DISTRIB_RELEASE="$GABU_VERSION"
DISTRIB_DESCRIPTION="$GABU_NAME"
EOF
  printf '\n%s %s (\\l)\n\n' "$GABU_NAME" "$GABU_VERSION" > /etc/issue
  cat > /etc/shells <<'EOF'
/bin/sh
/bin/bash
EOF
  cat > /etc/fstab <<EOF
PARTUUID=${GABU_DISK_ID}-01  /  ext4  defaults  1 1
EOF
  cat > /etc/profile <<'EOF'
export PATH=/usr/local/bin:/usr/bin:/usr/sbin
export LANG=$(. /etc/locale.conf 2>/dev/null; echo ${LANG:-C.UTF-8})
export INPUTRC=/etc/inputrc
PS1='\u@\h:\w\$ '
alias ls='ls --color=auto'
EOF
  cat > /etc/inputrc <<'EOF'
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[3~": delete-char
EOF
  cat > /etc/vimrc <<'EOF'
set nocompatible
set backspace=2
syntax on
EOF

  # utilizadores
  echo "root:$GABU_PASSWORD" | chpasswd
  id "$GABU_USER" &>/dev/null || useradd -m -s /bin/bash -G wheel,audio,video,input,users "$GABU_USER"
  echo "$GABU_USER:$GABU_PASSWORD" | chpasswd

  systemctl enable systemd-networkd systemd-resolved systemd-timesyncd
}

install_selftest() {
  mkdir -p /usr/lib/gabu /etc/gabu
  cat > /usr/lib/gabu/selftest.sh <<'EOF'
#!/bin/bash
# Auto-teste de arranque (activado por /etc/gabu/selftest). A saída vai para a consola série.
fail=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "GABU-TEST ok    $1"; else echo "GABU-TEST FALHOU $1"; fail=1; fi; }
chk "os-release"            'grep -q "Gabu Linux" /etc/os-release'
chk "systemd"               'systemctl --version'
chk "rede (networkd)"       'systemctl is-enabled systemd-networkd'
chk "gcc compila"           'cd /tmp && echo "int main(){return 0;}" > t.c && cc t.c -o t && ./t'
chk "dpkg amd64"            '[ "$(dpkg --print-architecture)" = amd64 ]'
chk "apt-get --version"     'apt-get --version'
chk "apt-get update"        'apt-get update'
chk "apt-get install"       'apt-get install -y gabu-hello'
chk "gabu-hello corre"      'gabu-hello | grep -q Gabu'
chk "dpkg -l gabu-hello"    'dpkg -s gabu-hello | grep -q "Status: install ok installed"'
if command -v mate-session >/dev/null 2>&1; then
  chk "Xorg instalado"      'command -v Xorg'
  chk "MATE instalado"      'command -v mate-session && command -v mate-panel && command -v marco && command -v caja'
fi
if [ $fail = 0 ]; then echo "GABU-SELFTEST: PASS"; else echo "GABU-SELFTEST: FAIL"; fi
systemctl poweroff
EOF
  cat > /usr/lib/gabu/desktop-probe.sh <<'EOF'
#!/bin/bash
# Espera até 5 min pelo mate-panel (activado por /etc/gabu/desktoptest)
for i in $(seq 1 60); do
  if pgrep -x mate-panel >/dev/null; then echo "GABU-DESKTOP: PASS"; exit 0; fi
  sleep 5
done
echo "GABU-DESKTOP: FAIL"
EOF
  chmod +x /usr/lib/gabu/*.sh
  cat > /etc/systemd/system/gabu-selftest.service <<'EOF'
[Unit]
Description=Gabu Linux auto-teste
ConditionPathExists=/etc/gabu/selftest
After=multi-user.target systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/lib/gabu/selftest.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/gabu-desktop-probe.service <<'EOF'
[Unit]
Description=Gabu Linux sonda do ambiente de trabalho
ConditionPathExists=/etc/gabu/desktoptest
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/lib/gabu/desktop-probe.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable gabu-selftest.service gabu-desktop-probe.service
}

do_linux() {
  make mrproper
  make defconfig
  scripts/kconfig/merge_config.sh -m .config "$GABU_ROOT_DIR/config/kernel.fragment"
  make olddefconfig
  make
  make modules_install
  install -Dm644 arch/x86/boot/bzImage /boot/vmlinuz-gabu
  install -m644 System.map /boot/System.map-gabu
  install -m644 .config /boot/config-gabu
}

if [ ! -e "$DONE/s4-config" ]; then configure_system; install_selftest; touch "$DONE/s4-config"; fi
build linux 'linux-[0-9]*.tar.*'
log "Stage 4 concluído."
