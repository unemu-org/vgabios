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
nix flake check      # std: check-286.sh, 32 KiB, 55 AA 40, zero checksum;
                     # std and probe: release SHA-256s
```

`std` is the standard ISA VGA build: the upstream source with no `VBE`,
`PCIBIOS`, `CIRRUS`, `BANSHEE` or `CPU386` define, so it is 80286 real-mode
code (8086/80186/80286 instructions). `nix build .#std386` gives the same build with `-DCPU386`, which keeps
upstream's 32-bit code paths.
nixpkgs marks dev86 as Linux-only; the flake lifts that, and it builds on macOS.

## Reproducibility

The same source must give the same ROM bytes on every system the flake
supports, because consumers pin the ROM by its SHA-256. The build fixes:

- nixpkgs: the revision pinned in `flake.nix`, so dev86, GCC and the other
  tools are the same versions everywhere.
- Preprocessor: unwrapped GCC 14.3.0 from that nixpkgs, run as
  `gcc -E -P -undef -nostdinc`, on every system. The flake does not use the
  stdenv compiler, which is clang on macOS and GCC on Linux. `-undef` drops the
  platform macros and `-nostdinc` the system headers. This source uses no
  predefined macros and includes only its own files, so with these flags the
  host does not change its preprocessed text.
- Tool flags: `bcc -C-c -D__i86__ -S -0` and `as86 -u -w- -g -0 -j -O`, as in
  `flake.nix`.
- Intermediate file names: `_rom_.c` (the bcc input), `rom.s` and `_rom_.s`.
  bcc with `-S` copies its input, file name included, into the assembly as
  comments, and the code it generates can change with the length of that
  text: with a 33-character input name instead of `_rom_.c`, one `jmp` became
  a `br`, which changed
  the ROM bytes. Any change to the preprocessed text can do the same, even in
  white space. The two `.s` names do not change the bytes; they stay fixed
  anyway.
- Version and date strings: `VGABIOS_VERS="0.8a-unemu"` and
  `VGABIOS_DATE="01 Jan 1980"`.

dev86 (bcc, as86) is compiled on each host by that host's compiler, and so is
the checksum tool. The pins above do not cover how those binaries behave; only
the hash check does. `nix flake check` compares the SHA-256s of
`vgabios-std.bin` and `int10-probe-1200.img` with `releaseSha256` in
`flake.nix`, so a system that builds other bytes fails the check. The check
runs only where someone runs it: before a release, run it on every system
consumers build on, at least x86_64-linux
(`nix build .#checks.x86_64-linux.release-sha256` on a Linux builder). A change
meant to alter either file updates those values, and the next release tag
states them.

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
- The std ROM and the probe image match `releaseSha256` on aarch64-darwin.
  x86_64-linux, aarch64-linux and x86_64-darwin are not verified yet.
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

1. Tag releases. The tag message states the source revision and the SHA-256 of
   the std ROM and of the probe image. unemupc98 fetches both by SHA-256
   (`vendor/vgabios/fetch.sh`) and lists the ROM in its firmware catalogue as
   open firmware.
