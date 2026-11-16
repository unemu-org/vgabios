# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 the contributors to the unemu fork of the LGPL VGABIOS.
{
  description = "LGPL VGABIOS fork for unemu machines: reproducible standard-VGA ROM builds";

  # Pinned nixpkgs: the ROM and probe bytes depend on its dev86, GCC and nasm
  # (README.unemu.md, "Reproducibility"). Moving it can change releaseSha256.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/62e0f05ede1da0d54515d4ea8ce9c733f12d9f08";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f system);
      pkgsFor = system: import nixpkgs { inherit system; };
      # nixpkgs marks dev86 Linux-only, but it builds and runs on macOS too.
      dev86For = pkgs: pkgs.dev86.overrideAttrs (old: {
        meta = old.meta // { platforms = nixpkgs.lib.platforms.unix; };
      });
      # Expected SHA-256s of the std ROM and the probe image; the release tag
      # states the same values. nix flake check fails when a build gives other
      # bytes on any system. A change meant to alter either file updates them.
      releaseSha256 = {
        std = "b867f3846f44be63b1b10febc1ce79c9435f5d1233c67a0b63164ab48359a582";
        int10-probe = "7c928cec8e49c04c91d1cb7194b5f508db3d86ac89be9867a7290eb04c11f1b4";
      };
      # One build variant of the ROM. `flags` are the upstream Makefile's
      # VGAFLAGS; the standard ISA VGA build uses none (no VBE, no PCI header).
      romFor = system: { name, flags }:
        let
          pkgs = pkgsFor system;
          dev86 = dev86For pkgs;
          # Fixed version and date strings make the ROM bytes reproducible.
          version = "0.9d-unemu";
          date = "01 Jan 1980";
          # bcc's code can change with the exact text it reads (white space,
          # file names), so every system preprocesses with GCC 14.3.0 from the
          # pinned nixpkgs, not the stdenv compiler (clang on macOS), with no
          # platform macros (-undef) and no system headers (-nostdinc). The
          # tool flags and intermediate file names below are part of the same
          # contract (README.unemu.md, "Reproducibility").
          gcc = pkgs.gcc14.cc;
        in
        pkgs.stdenv.mkDerivation {
          pname = "vgabios-${name}";
          inherit version;
          src = ./.;
          nativeBuildInputs = [ dev86 pkgs.gnused ];
          dontConfigure = true;
          buildPhase = ''
            runHook preBuild
            $CC -O2 -o biossums biossums.c
            ${gcc}/bin/gcc -E -P -undef -nostdinc vgabios.c ${flags} \
              '-DVGABIOS_VERS="${version}"' '-DVGABIOS_DATE="${date}"' > _rom_.c
            bcc -o rom.s -C-c -D__i86__ -S -0 _rom_.c
            sed -e 's/^\.text//' -e 's/^\.data//' rom.s > _rom_.s
            as86 _rom_.s -b rom.bin -u -w- -g -0 -j -O -l rom.txt
            ./biossums rom.bin
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp rom.bin $out/vgabios-${name}.bin
            cp rom.txt $out/vgabios-${name}.lst
            sha256sum $out/vgabios-${name}.bin | cut -d' ' -f1 > $out/vgabios-${name}.bin.sha256
            runHook postInstall
          '';
        };
    in
    {
      packages = forAll (system: rec {
        # Standard VGA for ISA machines (the unemu 286/386 AT profiles).
        std = romFor system { name = "std"; flags = ""; };
        # The same with upstream's 32-bit code paths (for 386+ machines).
        std386 = romFor system { name = "std386"; flags = "-DCPU386"; };
        default = std;
        # INT 10h probe: a bootable 1.2M floppy image (tests/unemu).
        int10-probe =
          let pkgs = pkgsFor system; in
          pkgs.stdenv.mkDerivation {
            pname = "vgabios-int10-probe";
            version = "0.9d-unemu";
            src = ./tests/unemu;
            nativeBuildInputs = [ pkgs.nasm ];
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              nasm -f bin -o probe.bin -l probe.lst int10-probe.asm
              cp probe.bin probe.img
              truncate -s 1228800 probe.img
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp probe.img $out/int10-probe-1200.img
              cp probe.lst $out/int10-probe.lst
              sha256sum $out/int10-probe-1200.img | cut -d' ' -f1 > $out/int10-probe-1200.img.sha256
              runHook postInstall
            '';
          };
      });

      # nix flake check: the std ROM must be 80286 code (scripts/check-286.sh)
      # and a valid option ROM (32 KiB, 55 AA, length byte, zero checksum), and
      # the std ROM and the probe image must match releaseSha256.
      checks = forAll (system:
        let
          pkgs = pkgsFor system;
          std = self.packages.${system}.std;
          probe = self.packages.${system}.int10-probe;
        in {
          release-sha256 = pkgs.runCommand "vgabios-release-sha256-check" { } ''
            check() {
              got=$(sha256sum "$2" | cut -d' ' -f1)
              [ "$got" = "$3" ] || { echo "$1: sha256 $got, expected $3" >&2; exit 1; }
            }
            check std ${std}/vgabios-std.bin ${releaseSha256.std}
            check int10-probe ${probe}/int10-probe-1200.img ${releaseSha256.int10-probe}
            echo "std ROM and probe image match releaseSha256"
            touch $out
          '';

          std-286 = pkgs.runCommand "vgabios-std-286-check" { } ''
            rom=${std}/vgabios-std.bin
            bash ${./scripts/check-286.sh} ${std}/vgabios-std.lst
            size=$(stat -c %s $rom)
            [ "$size" = 32768 ] || { echo "ROM size $size, not 32768" >&2; exit 1; }
            sig=$(od -An -tx1 -N3 $rom | tr -d ' \n')
            [ "$sig" = 55aa40 ] || { echo "ROM header $sig, not 55aa40" >&2; exit 1; }
            sum=$(od -An -v -tu1 $rom | awk '{ for (i = 1; i <= NF; i++) s += $i } END { print s % 256 }')
            [ "$sum" = 0 ] || { echo "ROM checksum $sum, not 0" >&2; exit 1; }
            echo "std ROM: 286 code, 32 KiB, 55 AA 40, zero checksum"
            touch $out
          '';
        });

      # nix run .#release-assets -- TAG [OUTDIR]: the ROM, the probe image and
      # the deterministic source archive of a release tag, built from the tag's
      # tree with this revision's tooling (scripts/release-assets.sh).
      apps = forAll (system:
        let
          pkgs = pkgsFor system;
          releaseAssets = pkgs.writeShellApplication {
            name = "release-assets";
            runtimeInputs = [ pkgs.gnutar pkgs.coreutils pkgs.gnused pkgs.gawk pkgs.git ];
            text = "NOTICE_TEMPLATE=${./release/source-notice.txt.in}\n"
              + builtins.readFile ./scripts/release-assets.sh;
          };
        in {
          release-assets = {
            type = "app";
            program = "${releaseAssets}/bin/release-assets";
            meta.description = "Build a release tag's ROM, probe image and source archive";
          };
        });

      devShells = forAll (system:
        let pkgs = pkgsFor system; in {
          default = pkgs.mkShell {
            packages = [ (dev86For pkgs) pkgs.gnumake pkgs.nasm ];
          };
        });
    };
}
