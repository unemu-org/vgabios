# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 the contributors to the unemu fork of the LGPL VGABIOS.
#
# Build the assets of a release tag from this repository's object store:
#   vgabios-std.bin                the flake output std at the tag
#   int10-probe-1200.img           the flake output int10-probe at the tag
#   vgabios-<version>-src.tar      the tag's tree as vgabios/ plus a NOTICE
#   SHA256SUMS
# The source archive is deterministic (member order, timestamps, owners and
# modes are fixed; the timestamp is the tag commit's time), so it has the same
# bytes on every host and matches the archive unemupc98's
# vendor/vgabios/fetch.sh writes. The tag's tree is built, never the working
# tree. Run it as: nix run .#release-assets -- TAG [OUTDIR]
# The ROM and probe SHA-256s must match the "sha256" lines of the tag message;
# with EXPECTED_SOURCE_SHA256 set, the archive's must match it too.
#
# release-assets in flake.nix prepends NOTICE_TEMPLATE (the store path of
# release/source-notice.txt.in) and runs this with GNU tar from the pinned
# nixpkgs; writeShellApplication adds set -euo pipefail.

tag="${1:?usage: release-assets TAG [OUTDIR]}"
out="${2:-release-assets}"
unset TAR_OPTIONS
umask 022
# Tags go into a flake URL and a sed script; allow only plain release names.
if [[ ! "$tag" =~ ^v[0-9][0-9A-Za-z.+-]*$ ]]; then
  echo "not a release tag name: $tag" >&2
  exit 1
fi

repo="$(git rev-parse --show-toplevel)"
rev="$(git -C "$repo" rev-parse --verify "refs/tags/$tag^{commit}")"
flake="git+file://$repo?ref=refs/tags/$tag&rev=$rev"
version="${tag#v}"
# release/source-notice.txt.in describes the 0.9d-based releases; the 0.8a
# ones (v0.8a-unemu.1 to .3) shipped with another NOTICE.
if ! git -C "$repo" merge-base --is-ancestor 6dca80563ee648f1ba221bfd2bb62622d838c71c "$rev"; then
  echo "$tag predates the 0.9d base (merge 6dca805); its NOTICE differs from release/source-notice.txt.in" >&2
  exit 1
fi
# The tag message states the ROM and probe SHA-256s: "<file> (...)" and then
# "  sha256 <hex>" on the next line.
tag_sha256() {
  git -C "$repo" cat-file tag "$tag" | awk -v f="$1" 'found && $1 == "sha256" { print $2; exit } index($0, f) { found = 1 }'
}
expected_rom="$(tag_sha256 vgabios-std.bin)"
expected_probe="$(tag_sha256 int10-probe-1200.img)"
if [ -z "$expected_rom" ] || [ -z "$expected_probe" ]; then
  echo "the message of $tag states no sha256 for vgabios-std.bin or int10-probe-1200.img" >&2
  exit 1
fi
source_name="vgabios-$version-src"
nix=(nix --extra-experimental-features "nix-command flakes")

echo "building $tag ($rev)"
rom_store="$("${nix[@]}" build --no-link --print-out-paths "$flake#std")"
probe_store="$("${nix[@]}" build --no-link --print-out-paths "$flake#int10-probe")"

work="$(mktemp -d)"
# The source copy comes from the read-only store; make it removable.
trap 'chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$out"

cp "$rom_store/vgabios-std.bin" "$work/vgabios-std.bin"
size="$(wc -c < "$work/vgabios-std.bin" | tr -d '[:space:]')"
header="$(od -An -tx1 -N3 "$work/vgabios-std.bin" | tr -d ' \n')"
sum="$(od -An -v -tu1 "$work/vgabios-std.bin" | awk '{ for (i = 1; i <= NF; i++) s += $i } END { print s % 256 }')"
if [ "$size" -ne 32768 ] || [ "$header" != 55aa40 ] || [ "$sum" -ne 0 ]; then
  echo "invalid video ROM: expected 32768 bytes, header 55aa40 and byte sum 0" >&2
  exit 1
fi
cp "$probe_store/int10-probe-1200.img" "$work/int10-probe-1200.img"
probe_size="$(wc -c < "$work/int10-probe-1200.img" | tr -d '[:space:]')"
if [ "$probe_size" -ne 1228800 ]; then
  echo "unexpected probe floppy size: $probe_size bytes (expected 1228800)" >&2
  exit 1
fi
rom_sha256="$(sha256sum "$work/vgabios-std.bin" | cut -d' ' -f1)"
probe_sha256="$(sha256sum "$work/int10-probe-1200.img" | cut -d' ' -f1)"
check() {
  if [ "$2" != "$3" ]; then
    echo "$1: sha256 $2, but $4 states $3" >&2
    exit 1
  fi
}
check vgabios-std.bin "$rom_sha256" "$expected_rom" "the $tag message"
check int10-probe-1200.img "$probe_sha256" "$expected_probe" "the $tag message"

# The tree Nix built both files from, and its commit time.
# shellcheck disable=SC2016 # the Nix expression, not the shell, expands ${...}
source_info="$(VGABIOS_FLAKE_REF="$flake" "${nix[@]}" eval --raw --impure --expr \
  'let flake = builtins.getFlake (builtins.getEnv "VGABIOS_FLAKE_REF"); in "${toString flake.lastModified} ${flake.outPath}"')"
source_epoch="${source_info%% *}"
source_tree="${source_info#* }"
stage="$work/source/$source_name"
mkdir -p "$stage"
cp -R "$source_tree" "$stage/vgabios"
chmod -R u+w "$stage"
# Per-clone issue-tracker settings; untracked since v0.8a-unemu.3, removed
# here as a guard.
rm -f "$stage/vgabios/.beads/config.yaml"
sed -e "s/@VERSION@/$version/g" -e "s/@TAG@/$tag/g" -e "s/@REVISION@/$rev/g" \
  -e "s/@ROM_SHA256@/$rom_sha256/g" -e "s/@PROBE_SHA256@/$probe_sha256/g" \
  "$NOTICE_TEMPLATE" > "$stage/NOTICE"
LC_ALL=C tar --create --file="$work/source.tar" --directory="$work/source" \
  --format=ustar --sort=name --hard-dereference --mtime="@$source_epoch" \
  --owner=0 --group=0 --numeric-owner --mode='a=rX,u+w,ug-s' "$source_name"

if [ -n "${EXPECTED_SOURCE_SHA256:-}" ]; then
  check "$source_name.tar" "$(sha256sum "$work/source.tar" | cut -d' ' -f1)" \
    "$EXPECTED_SOURCE_SHA256" EXPECTED_SOURCE_SHA256
fi

chmod 0644 "$work/vgabios-std.bin" "$work/int10-probe-1200.img"
mv "$work/vgabios-std.bin" "$work/int10-probe-1200.img" "$out/"
mv "$work/source.tar" "$out/$source_name.tar"
(cd "$out" && sha256sum vgabios-std.bin int10-probe-1200.img "$source_name.tar" > SHA256SUMS)
cat "$out/SHA256SUMS"
