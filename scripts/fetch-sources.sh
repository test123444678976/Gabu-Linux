#!/usr/bin/env bash
# Descarrega as fontes do LFS usando as listas oficiais do livro (versões sempre coerentes).
source "$(dirname "$(readlink -f "$0")")/lib.sh"
cd "$SRC"

base=""
for b in "${LFS_BOOK_BASES[@]}"; do
  for w in wget-list-systemd wget-list; do
    if curl -fsSL "$b/$w" -o wget-list.tmp 2>/dev/null; then base=$b; break 2; fi
  done
done
[ -n "$base" ] || die "não consegui obter a wget-list do livro LFS"
mv wget-list.tmp wget-list
curl -fsSL "$base/md5sums" -o md5sums || die "sem md5sums"
log "Lista de fontes: $base"

wget -nv -c --tries=3 --timeout=30 -i wget-list -P "$SRC" || log "alguns downloads falharam, a tentar espelhos"

failed() { md5sum -c md5sums --quiet 2>&1 | sed -nE 's/^(.*): FAILED.*$/\1/p; s/^md5sum: (.*): No such file.*$/\1/p'; }
for f in $(failed | sort -u); do
  for m in "${LFS_MIRRORS[@]}"; do
    rm -f "$f"; wget -nv -O "$f" "$m/$f" && break || true
  done
done
md5sum -c md5sums --quiet || die "md5 inválido em algumas fontes"
log "Fontes LFS OK: $(ls | wc -l) ficheiros"
chmod -R a+rX "$SRC"
