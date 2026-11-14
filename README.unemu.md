# vgabios (unemu fork)

A fork of the **LGPL VGABIOS** (the video BIOS used by Bochs and QEMU) for the
machines of the unemu family, starting with
[unemupc98](https://github.com/unemu-org) (an IBM PC/AT-class emulator). The
emulator needs an open video BIOS that runs on an **80286** with its
register-level VGA, so that public machine images (DOS games and software)
never depend on proprietary ROMs.

- Upstream: <https://savannah.nongnu.org/projects/vgabios/>, release
  `vgabios-0.8a` (tarball SHA-256
  `481042240ef0f1c918780c92a6bb42ad4d3f5d989b29502fa7ee7faf13a041b9`).
- The first commit is that release verbatim; every later commit is our change.
- Licence: GNU LGPL 2.1, see `COPYING`. Copyright the LGPL VGABios developers
  and the contributors to this fork.

## Build

```sh
nix build            # result/vgabios-std.bin, .lst (listing), .bin.sha256
nix develop          # dev86 (bcc, as86, ld86), make, nasm/ndisasm
scripts/check-286.sh result/vgabios-std.lst
```

`std` is the standard ISA VGA build: the upstream source with no `VBE`,
`PCIBIOS`, `CIRRUS`, `BANSHEE` or `CPU386` define, so it is 80286 real-mode
code (8086/80186/80286 instructions). `nix build .#std386` gives the same build with `-DCPU386`, which keeps
upstream's 32-bit code paths. The version string and date are fixed
in `flake.nix`, so the same source always gives the same ROM bytes.
nixpkgs marks dev86 as Linux-only; the flake lifts that, and it builds on macOS.

## INT 10h probe

`nix build .#int10-probe` gives `int10-probe-1200.img`, a bootable 1.2M
floppy built from `tests/unemu/int10-probe.asm`, with its listing and SHA-256.
It checks the video BIOS in modes 03h, 0Dh and 13h by reading registers and
video memory back: mode set and BIOS data area, the 8x16 font in plane 2,
cursor, teletype, scroll, active page (CRTC start), pixel write/read, plane
bits, pel panning, DAC and AH=1Ch save/restore. It then returns to mode 03h,
prints `name ok` or `name FAIL` for each check and the number of failures, and
halts. The checks do not judge the picture: scanout belongs to the emulator's
own tests. unemupc98 uses the image as an open test fixture, pinned by its
SHA-256.

## Status

- The `std` build is 32 KiB, starts with `55 AA`, its 8-bit checksum is zero,
  and `scripts/check-286.sh` finds no 386-only instructions in it. The check
  reads both the mnemonics and the opcode bytes of the as86 listing (386
  prefixes 66/67/64/65 and 0F opcodes other than 0F00-0F06).
- `std386` gives the same bytes as the upstream 0.8a source built with no
  define.
- On unemupc98's open AT profile (`at-games-open` with a VGA card, the ROM at
  C0000) FreeDOS boots to the prompt and the INT 10h probe reports no failure.

## Deviations from upstream

- `CPU386` define (`vgabios.c`): upstream 0.8a uses 32-bit instructions even in
  a build with no define, so it does not run on an 80286. `CPU386` selects
  upstream's 32-bit code; `VBE`, `CIRRUS`, `BANSHEE` and `PCIBIOS` imply it, so
  every upstream Makefile build gives the same code as before. Without
  `CPU386`:
  - The ROM is assembled with `use16 286`, not `use16 386`. With `386`, as86
    `-j` turns bcc's out-of-range conditional branches into near `Jcc rel16`
    (`0F 8x`), which an 80286 does not have; with `286` it emits a short
    inverted `Jcc` over a `JMP rel16`.
  - INT 10h AH=1Ch (save/restore video state) copies the INT 1Fh and INT 43h
    vectors with two 16-bit moves each, not one `mov eax`. The buffer layout
    does not change.
  - `pci_read_reg` (32-bit PCI configuration access) is not assembled. Only
    the `VBE`, `CIRRUS` and `BANSHEE` code calls it.

## Plan

1. Make `check-286.sh` part of the build (a Nix check), so a regression fails
   the build.
2. Tag releases. The tag message states the source revision and the SHA-256 of
   the std ROM and of the probe image. unemupc98 fetches both by SHA-256
   (`vendor/vgabios/fetch.sh`) and lists the ROM in its firmware catalogue as
   open firmware.
