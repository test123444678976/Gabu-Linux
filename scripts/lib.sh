#!/usr/bin/env bash
# Gabu Linux - funções comuns (usadas no host, como utilizador lfs, e dentro do chroot)
set -Eeuo pipefail

GABU_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/gabu.conf
source "$GABU_ROOT_DIR/config/gabu.conf"

# Dentro do chroot a raiz é "/", fora é $LFS
if [ -n "${IN_CHROOT:-}" ]; then GROOT=""; else GROOT="$LFS"; fi
SRC="$GROOT/sources"
BUILD="$GROOT/build"
STATE="$GROOT/.gabu"
DONE="$STATE/done"
LOGS="$STATE/logs"
STAGE="${STAGE:-x}"
export MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}"
mkdir -p "$SRC" "$BUILD" "$DONE" "$LOGS"

log() { printf '\033[1;32m[gabu %s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\033[1;31m[gabu ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

# tarball <glob>  -> caminho do tarball mais recente (ignora patches)
tarball() {
  local f
  f=$(find "$SRC" -maxdepth 1 -iname "$1" ! -name '*.patch' ! -name '*.diff' | sort -V | tail -n1)
  [ -n "$f" ] || die "tarball não encontrado em $SRC: $1"
  echo "$f"
}
patchfile() { find "$SRC" -maxdepth 1 -name "$1" | sort -V | head -n1; }
# ver <nome> -> 2.43.1 ; ver2 <nome> -> 2.43
ver()  { basename "$(tarball "$1-[0-9]*.tar.*")" | sed -E "s/^$1-([0-9][0-9.]*[0-9]).*/\1/I"; }
ver2() { ver "$1" | cut -d. -f1,2; }

# build <nome> [glob-tarball] [função]
# Extrai o tarball, corre a função (por omissão do_<nome>) com set -e, regista log e marca como feito.
build() {
  local name=$1 pat=${2:-} fn=${3:-} tb rc logf
  [ -n "$pat" ] || pat="$name-[0-9]*.tar.*"
  [ -n "$fn" ]  || fn="do_${name//[-.+]/_}"
  logf="$LOGS/$STAGE-$name.log"
  if [ -e "$DONE/$STAGE-$name" ]; then log "já feito: $name"; return 0; fi
  tb=$(tarball "$pat")
  log "A compilar $name  ($(basename "$tb"))"
  rm -rf "${BUILD:?}/$name"; mkdir -p "$BUILD/$name"
  tar -xf "$tb" -C "$BUILD/$name" --strip-components=1
  pushd "$BUILD/$name" >/dev/null
  set +e
  ( set -Eeuo pipefail; "$fn" ) >"$logf" 2>&1 </dev/null
  rc=$?
  set -e
  popd >/dev/null
  if [ $rc -ne 0 ]; then
    tail -n 80 "$logf" >&2
    die "falhou: $name (log completo: $logf)"
  fi
  rm -rf "${BUILD:?}/$name"
  touch "$DONE/$STAGE-$name"
}

# Opções meson filtradas/normalizadas contra meson.options (ver mesonopts.py)
mopts() { python3 "$GABU_ROOT_DIR/scripts/mesonopts.py" "${MESON_SRC:-..}" "$@"; }

# Instalar módulo Python por wheel local (receitas LFS)
pyinst() { pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"; pip3 install --no-index --find-links dist "$1"; }
