#!/usr/bin/env python3
"""Filtra e normaliza opções -Dnome=valor contra o meson.options do projecto.

Uso: mesonopts.py <dir-fontes> -Da=b -Dc=d ...
Opções que não existem são descartadas; valores true/false/enabled/disabled são
convertidos para o tipo real da opção (boolean ou feature).
"""
import os
import re
import sys

src, args = sys.argv[1], sys.argv[2:]
text = ""
for f in ("meson.options", "meson_options.txt"):
    p = os.path.join(src, f)
    if os.path.exists(p):
        text += open(p, encoding="utf-8", errors="ignore").read()

types = {
    m.group(1): m.group(2)
    for m in re.finditer(
        r"option\(\s*['\"]([^'\"]+)['\"]\s*,[^)]*?type\s*:\s*['\"](\w+)['\"]", text, re.S
    )
}
TRUE = {"true", "yes", "enabled", "on", "1"}
FALSE = {"false", "no", "disabled", "off", "0"}

for a in args:
    if not a.startswith("-D"):
        print(a)
        continue
    k, _, v = a[2:].partition("=")
    t = types.get(k)
    if t is None:
        continue
    lv = v.lower()
    if t == "boolean":
        v = "true" if lv in TRUE else "false" if lv in FALSE else v
    elif t == "feature":
        v = "enabled" if lv in TRUE else "disabled" if lv in FALSE else v
    print(f"-D{k}={v}")
