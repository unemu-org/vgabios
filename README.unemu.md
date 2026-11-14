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
`PCIBIOS`, `CIRRUS` or `BANSHEE` define. The version string and date are fixed
in `flake.nix`, so the same source always gives the same ROM bytes.
nixpkgs marks dev86 as Linux-only; the flake lifts that, and it builds on macOS.

## Status

- The upstream 0.8a `std` build is 32 KiB, starts with `55 AA`, and its 8-bit
  checksum is zero.
- `scripts/check-286.sh` still finds 386-only instructions, so the ROM is not
  yet safe on a 286:
  - `vgabios.c` ~3881/3883 and ~4067/4070: INT 10h AH=1Ch save/restore video
    state copies the INT 1Fh and INT 43h vectors with `mov eax, …`. Replace
    them with two 16-bit moves each.
  - `vgabios.c` ~4735: `pci_read_reg` uses 32-bit PCI configuration access.
    It is only needed by `PCIBIOS` builds; put it under `#ifdef PCIBIOS`.

## Plan

1. Remove the 386-only instructions above, and make `check-286.sh` part of the
   build (a Nix check), so a regression fails the build.
2. Boot the ROM in unemupc98's `at-games-open` profile (open AT BIOS, VGA card):
   text mode 3, EGA mode 0Dh with pel panning, mode 13h. Fix what breaks, with
   a note in this file for each deviation from upstream.
3. Tag releases. unemupc98 fetches the ROM by SHA-256 (`vendor/vgabios/fetch.sh`)
   and lists it in its firmware catalogue as open firmware.
