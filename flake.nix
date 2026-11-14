{
  description = "LGPL VGABIOS fork for unemu machines: reproducible standard-VGA ROM builds";

  # Same nixpkgs revision as unemupc98, so both repositories share one toolchain.
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
      # One build variant of the ROM. `flags` are the upstream Makefile's
      # VGAFLAGS; the standard ISA VGA build uses none (no VBE, no PCI header).
      romFor = system: { name, flags }:
        let
          pkgs = pkgsFor system;
          dev86 = dev86For pkgs;
          # Fixed version and date strings make the ROM bytes reproducible.
          version = "0.8a-unemu";
          date = "01 Jan 1980";
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
            $CC -E -P vgabios.c ${flags} \
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
      });

      devShells = forAll (system:
        let pkgs = pkgsFor system; in {
          default = pkgs.mkShell {
            packages = [ (dev86For pkgs) pkgs.gnumake pkgs.nasm ];
          };
        });
    };
}
