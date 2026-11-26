# Gabu Linux

Distribuição Linux construída **de raiz segundo o Linux From Scratch 13.1 (systemd)**, com:

- **apt + dpkg** compilados a partir do código-fonte do Debian (repositório local de teste incluído)
- **MATE 1.28** compilado à mão sobre Xorg + GTK3 (estilo BLFS)
- imagem de disco **bootável em QEMU** (MBR + GRUB BIOS), com testes automáticos no **GitHub Actions**

> **Estado: v0.1 – andaime completo mas ainda não executado.** Os scripts seguem o livro LFS e o BLFS,
> mas nunca correram de ponta a ponta. Espera algumas rondas de correcções no CI (sobretudo nos
> jobs 5–6, Xorg/GTK/MATE). Cola o log do job que falhar e corrige-se.

## Como funciona

| Job | O que faz | Saída |
|---|---|---|
| 1 `toolchain` | host + fontes oficiais LFS + caps. 5–6 | `state-toolchain` |
| 2 `system` | caps. 7–8 (sem suites de testes) | `state-system` |
| 3 `core` | configuração, kernel, **dpkg + apt** | `state-core` |
| 4 `image-core` | imagem + **teste QEMU** (apt update/install, gcc, dpkg) | `image-core` (.qcow2) |
| 5 `desktop-base` | Xorg, cairo/pango/GTK3, librsvg (Rust binário) | `state-desktop-base` |
| 6 `desktop-mate` | MATE (marco, panel, caja, terminal…) | `state-desktop` |
| 7 `image-desktop` | imagem + testes QEMU + captura de ecrã | `image-desktop` |

O estado passa entre jobs como `tar.zst` (cada job < 6 h). `Re-run failed jobs` retoma de onde falhou.
Ao criar uma tag `v*` as imagens são anexadas a uma release.

## Testar localmente

```bash
qemu-system-x86_64 -enable-kvm -m 4096 -smp 4 -cpu host \
  -drive file=gabu-desktop-0.1.0.qcow2,if=virtio -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -vga std
```
Utilizadores: `root` / `gabu` (palavra-passe `gabu`, **só desenvolvimento**). Na imagem desktop,
o `gabu` entra automaticamente na tty1 e arranca o MATE via `startx`.

Num apt dentro da imagem:
```bash
apt-get update && apt-get install gabu-hello && gabu-hello
```

## Decisões e limitações

- **Versões**: nada fixo. As fontes LFS vêm da `wget-list` oficial; Xorg/GNOME/MATE/apt resolvem-se em CI
  pelo índice do upstream (`config/packages.manifest`, `scripts/fetch-extra.sh`).
- **Sem `-march=native`** em lado nenhum (a imagem tem de arrancar em qualquer CPU x86-64).
- **Testes das suites do LFS desligados** (tempo de CI) → também não há tcl/expect/dejagnu.
- **apt**: o repositório é um *flat repo* local (`/var/lib/gabu/repo`, `trusted=yes`). Falta GnuPG para
  repositórios assinados e um repositório público (ex.: GitHub Pages). Os pacotes compilados à mão
  (incl. MATE) **não estão registados no dpkg**; o passo seguinte natural é empacotá-los em `.deb`.
- **Sem PAM nem gestor de sessão**: autologin + `startx` + Xorg com `Xorg.wrap` setuid. Roadmap:
  Linux-PAM, shadow com PAM, polkit, LightDM.
- Só **BIOS** (GRUB `i386-pc`); falta UEFI.
- Rust (binário oficial) fica instalado por causa do librsvg; pode removê-lo no fim.

## Estrutura

```
config/gabu.conf            identidade, locale, caminhos
config/kernel.fragment      opções do kernel (systemd + virtio + DRM)
config/packages.manifest    apt, Xorg, GTK, MATE (resolvido em CI)
scripts/stage1..5-*.sh      build por fases
scripts/make-image.sh       disco MBR + ext4 + GRUB + repo apt local
scripts/qemu-test.sh        testes de arranque (série) e do desktop (captura)
.github/workflows/build.yml pipeline
```
