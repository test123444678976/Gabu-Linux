#!/usr/bin/env bash
# Uso: fetch-extra.sh <secção do packages.manifest>   (corre no HOST: tem curl/python)
# Resolve sempre a última versão adequada e guarda como $LFS/sources/<nome>-<versão>.tar.*
source "$(dirname "$(readlink -f "$0")")/lib.sh"
section=${1:?secção}
MANIFEST="$GABU_ROOT_DIR/config/packages.manifest"

get() { curl -fsSL --retry 3 --retry-delay 2 "$@"; }
re()  { printf '%s-[0-9][0-9.]*\\.tar\\.(xz|gz|bz2)' "$(printf '%s' "$1" | sed 's/[+.]/\\&/g')"; }

# idx_latest <url-do-índice> <ERE do nome do ficheiro> -> URL completo
idx_latest() {
  local u=$1 rx=$2 f
  f=$(get "$u" | grep -oE 'href="[^"]+"' | sed -E 's/^href="//; s/"$//; s@.*/@@' \
      | sed 's/%2[Bb]/+/g' | grep -E "^($rx)\$" | sort -V | tail -n1) || true
  [ -n "$f" ] || return 1
  echo "${u%/}/$f"
}
gh_tag() { local t; t=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest"); echo "${t##*/}"; }

resolve() {  # resolve <nome> <origem> -> URL
  local n=$1 kind=${2%%:*} rest=${2#*:}
  case $kind in
    url|raw) echo "$rest" ;;
    xorg)  idx_latest "https://xorg.freedesktop.org/archive/individual/${rest%%/*}/" "$(re "${rest#*/}")" ;;
    mate)  idx_latest "https://pub.mate-desktop.org/releases/$MATE_SERIES/" "$(re "$rest")" ;;
    gh)    echo "https://github.com/$rest/archive/refs/tags/$(gh_tag "$rest").tar.gz" ;;
    ghrel) local repo=${rest%%|*} rx=${rest#*|} tag a
           tag=$(gh_tag "$repo")
           a=$(get "https://github.com/$repo/releases/expanded_assets/$tag" | grep -oE 'href="[^"]+"' \
               | sed -E 's/^href="//; s/"$//' | grep -E "/($rx)\$" | head -n1)
           [ -n "$a" ] && echo "https://github.com$a" ;;
    idx)   local url=${rest%%|*} pat=${rest#*|}
           if [[ $pat == *[\\\(\[]* ]]; then idx_latest "$url" "$pat"; else idx_latest "$url" "$(re "$pat")"; fi ;;
    gl)    local tag
           tag=$(get "https://gitlab.freedesktop.org/api/v4/projects/${rest//\//%2F}/repository/tags?per_page=1" \
                 | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["name"])')
           echo "https://gitlab.freedesktop.org/$rest/-/archive/$tag/$(basename "$rest")-$tag.tar.gz" ;;
    gnome) local m=${rest%%:*} ser="" d u
           [[ $rest == *:* ]] && ser=${rest#*:}
           if [ -n "$ser" ]; then
             idx_latest "https://download.gnome.org/sources/$m/$ser/" "$(re "$m")"; return
           fi
           for d in $(get "https://download.gnome.org/sources/$m/" | grep -oE 'href="[0-9]+(\.[0-9]+)?/"' \
                      | grep -oE '[0-9]+(\.[0-9]+)?' | awk -F. 'NF==1 || $2%2==0' | sort -rV); do
             if u=$(idx_latest "https://download.gnome.org/sources/$m/$d/" "$(re "$m")"); then echo "$u"; return; fi
           done; return 1 ;;
    rust)  local v
           v=$(get https://static.rust-lang.org/dist/channel-rust-stable.toml | awk '/^\[pkg.rust\]/{f=1} f&&/^version/{print $3; exit}' | tr -d '"')
           echo "https://static.rust-lang.org/dist/rust-$v-x86_64-unknown-linux-gnu.tar.xz" ;;
    *) die "origem desconhecida: $2" ;;
  esac
}

localname() {  # localname <nome> <url>
  local n=$1 base v ext
  base=$(basename "${2%%\?*}")
  ext=$(printf '%s' "$base" | grep -oE '\.tar\.(xz|gz|bz2)$|\.tgz$' || true)
  [ -n "$ext" ] || ext=.tar.gz
  v=$(printf '%s' "${base#"$n"}" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)
  [ -n "$v" ] || v=$(printf '%s' "$base" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)
  [ -n "$v" ] || v=0
  echo "$n-$v$ext"
}

section_cur=""
while IFS= read -r line; do
  case $line in ''|\#*) continue ;; \[*\]) section_cur=${line//[\[\]]/}; continue ;; esac
  [ "$section_cur" = "$section" ] || continue
  IFS=';' read -r name spec _ _ <<<"$line"
  url=$(resolve "$name" "$spec") || die "não consegui resolver $name ($spec)"
  [ -n "$url" ] || die "URL vazio para $name"
  out="$SRC/$(localname "$name" "$url")"
  if [ "${spec%%:*}" = raw ]; then
    out="$SRC/$name-1.0.tar.gz"
    if [ ! -e "$out" ]; then
      t=$(mktemp -d); mkdir "$t/$name-1.0"; get -o "$t/$name-1.0/$(basename "$url")" "$url"
      tar -C "$t" -czf "$out" "$name-1.0"; rm -rf "$t"
    fi
  elif [ ! -e "$out" ]; then
    get -o "$out" "$url" || die "download falhou: $url"
  fi
  log "$name -> $(basename "$out")"
done < "$MANIFEST"
chmod -R a+rX "$SRC"
