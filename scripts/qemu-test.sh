#!/usr/bin/env bash
# Uso: qemu-test.sh <core|desktop> <imagem.img>
#   core    -> arranca, corre /usr/lib/gabu/selftest.sh (apt, dpkg, gcc...) e procura "GABU-SELFTEST: PASS"
#   desktop -> arranca, espera pelo mate-panel ("GABU-DESKTOP: PASS") e guarda uma captura de ecrã
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo -E bash "$0" "$@"
mode=${1:?core|desktop}; img=${2:?imagem}
out=${OUT:-out}; mkdir -p "$out"
work=$(mktemp -d)
qpid=""
cleanup() { [ -z "$qpid" ] || kill "$qpid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

# Copia a imagem e marca o modo de teste dentro dela (o GRUB real continua a ser usado)
cp --sparse=always "$img" "$work/test.img"
loop=$(losetup -Pf --show "$work/test.img")
mkdir "$work/m"; mount "${loop}p1" "$work/m"
mkdir -p "$work/m/etc/gabu"
if [ "$mode" = core ]; then touch "$work/m/etc/gabu/selftest"; else touch "$work/m/etc/gabu/desktoptest"; fi
umount "$work/m"; losetup -d "$loop"

KVM=(-cpu max)
[ -w /dev/kvm ] && KVM=(-enable-kvm -cpu host)
serial="$out/serial-$mode.log"; : > "$serial"

qemu-system-x86_64 -machine q35 -m 4096 -smp 4 "${KVM[@]}" \
  -drive file="$work/test.img",if=virtio,format=raw \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -vga std -display none -serial "file:$serial" \
  -monitor "unix:$work/mon,server,nowait" -no-reboot &
qpid=$!

if [ "$mode" = core ]; then want='GABU-SELFTEST: PASS'; bad='GABU-SELFTEST: FAIL'
else want='GABU-DESKTOP: PASS'; bad='GABU-DESKTOP: FAIL'; fi

deadline=$((SECONDS + ${TIMEOUT:-1500}))
while ! grep -q "$want" "$serial" && ! grep -q "$bad" "$serial" \
      && kill -0 "$qpid" 2>/dev/null && [ $SECONDS -lt $deadline ]; do sleep 5; done

if [ "$mode" = desktop ] && grep -q "$want" "$serial"; then
  sleep 10   # deixar o painel desenhar
  echo "screendump $out/screen.ppm" | socat - "UNIX-CONNECT:$work/mon" >/dev/null
  sleep 2
  convert "$out/screen.ppm" "$out/screen.png"
  sd=$(convert "$out/screen.png" -format '%[fx:standard_deviation]' info:)
  echo "desvio-padrão da captura: $sd"
  awk -v s="$sd" 'BEGIN{exit !(s>0.02)}' || { echo "captura praticamente uniforme (ecrã vazio?)"; exit 1; }
fi
echo quit | socat - "UNIX-CONNECT:$work/mon" >/dev/null 2>&1 || true

if grep -q "$want" "$serial"; then echo "TESTE $mode: PASS"; exit 0; fi
echo "TESTE $mode: FALHOU. Fim do log série:"; tail -n 60 "$serial"; exit 1
