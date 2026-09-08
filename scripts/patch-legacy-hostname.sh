#!/usr/bin/env bash
#
# patch-legacy-hostname.sh - one-time post-processing workaround
#
# Takes a built .fw archive and rewrites the rootfs erlinit.config hostname
# from "-n phyboard-pollux" back to "-n phyboard-pollux-<SERIAL>" for the
# single legacy Jetson-connected unit that expects the old serial-suffixed
# hostname and cannot be changed.
#
# Usage: patch-legacy-hostname.sh <input.fw> [output.fw]
#
#   output.fw defaults to <input>_LEGACY-HOSTNAME.fw next to the input.
#   The serial suffix defaults to 00000000; override with LEGACY_SERIAL=nnnnnnnn.
#
# Requires: unzip, zip, unsquashfs/mksquashfs (squashfs-tools >= 4.6, for
# pseudofiles with embedded data), python3, fwup.
#
# How it works:
#   1. unpack the .fw (a plain zip)
#   2. dump the rootfs to a pseudofile (metadata + embedded file data) and
#      rebuild it from that alone, swapping in a patched erlinit.config.
#      The tree is never extracted to disk: uid/gid/modes/device nodes need
#      no root this way, and case-colliding paths (e.g. xt_tcpmss.ko vs
#      xt_TCPMSS.ko) survive macOS's case-insensitive filesystem.
#   3. recompute length + blake2b-256 in the meta.conf rootfs.img stanza
#   4. re-zip with meta.conf as the first entry (fwup streams the archive)
#   5. verify: fwup parses it, the patched hostname line is present, and the
#      original/patched file listings differ in exactly that one file
#      (directory inode sizes may shift; that is squashfs packing, not content)

set -euo pipefail

LC_ALL=C
LANG=C
export LC_ALL LANG

SERIAL="${LEGACY_SERIAL:-00000000}"

usage() { echo "Usage: $(basename "$0") <input.fw> [output.fw]"; }

err() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 1; }

for tool in unzip zip unsquashfs mksquashfs python3 fwup; do
    command -v "$tool" >/dev/null 2>&1 || err "required tool not found: $tool"
done

# "readlink -f" that also works on BSD/macOS
readlink_f() {
    cd "$(dirname "$1")" >/dev/null
    local filename="$(basename "$1")"
    if [[ -h "$filename" ]]; then
        readlink_f "$(readlink "$filename")"
    else
        echo "$(pwd -P)/$filename"
    fi
}

input_fw="$(readlink_f "$1")"
[[ -f "$input_fw" ]] || err "can't open $input_fw"

if [[ $# -eq 2 ]]; then
    output_fw="$2"
    case "$output_fw" in
        /*) ;;
        *) output_fw="$(pwd -P)/$output_fw" ;;
    esac
else
    output_fw="${input_fw%.fw}_LEGACY-HOSTNAME.fw"
fi
[[ "$output_fw" != "$input_fw" ]] || err "output would overwrite input"

if [[ -n "${TMPDIR:-}" && -e "${TMPDIR:-}" ]]; then
    workdir=$(mktemp -d "$TMPDIR/patch-legacy-hostname.XXXXXXXXXX")
else
    workdir=$(mktemp -d)
fi
case "$workdir" in
    *" "*) err "work directory path contains spaces (TMPDIR=$TMPDIR); mksquashfs pseudo commands can't cope" ;;
esac
trap 'rm -rf "$workdir"' EXIT

echo "==> Unpacking $(basename "$input_fw")"
# Remember the original entry order; the manifest must stay the first entry.
unzip -Z1 "$input_fw" > "$workdir/entries.txt"
[[ "$(head -n1 "$workdir/entries.txt")" == "meta.conf" ]] \
    || err "unexpected archive layout: first entry is not meta.conf"
grep -qx 'data/rootfs.img' "$workdir/entries.txt" \
    || err "archive has no data/rootfs.img"
mkdir "$workdir/fw"
unzip -q "$input_fw" -d "$workdir/fw"

cd "$workdir/fw"

# Capture the original superblock parameters and file listing for later checks.
unsquashfs -s data/rootfs.img > ../superblock.orig
block_size=$(awk '/^Block size/ {print $3}' ../superblock.orig)
compression=$(awk '/^Compression/ {print $2}' ../superblock.orig)
[[ -n "$block_size" && -n "$compression" ]] \
    || err "could not read block size/compression from original superblock"
unsquashfs -n -ll data/rootfs.img | grep 'squashfs-root' > ../listing.orig

echo "==> Preparing patched erlinit.config"
unsquashfs -n -q -d ../cfg data/rootfs.img etc/erlinit.config >/dev/null 2>&1
config=../cfg/etc/erlinit.config
[[ -f "$config" ]] || err "no etc/erlinit.config in rootfs"
if grep -q '^-n phyboard-pollux-' "$config"; then
    err "erlinit.config already has a suffixed hostname ($(grep '^-n' "$config")) - already patched?"
fi
grep -qx -- '-n phyboard-pollux' "$config" \
    || err "expected line '-n phyboard-pollux' not found in erlinit.config"
sed -e "s/^-n phyboard-pollux\$/-n phyboard-pollux-${SERIAL}/" "$config" \
    > "$workdir/erlinit.patched"
grep -qx -- "-n phyboard-pollux-${SERIAL}" "$workdir/erlinit.patched" \
    || err "sed failed to produce the patched hostname line"

echo "==> Rebuilding rootfs.img (-b $block_size -comp $compression)"
# Dump metadata + embedded data; nothing is extracted to disk.
unsquashfs -pf ../pseudofile data/rootfs.img >/dev/null

# Swap the erlinit.config entry: its "R" definition (data embedded in the
# pseudofile) becomes an "F" definition reading the patched file, keeping the
# original timestamp/mode/uid/gid. Also lift the root-dir attributes, which
# mksquashfs only honours via -root-* options, not via the "/" pseudo entry.
root_attrs=$(python3 - "$workdir" <<'EOF'
import re, sys

workdir = sys.argv[1]
pf = f"{workdir}/pseudofile"
marker = b"# START OF DATA - DO NOT MODIFY"
data = open(pf, "rb").read()
idx = data.index(marker)
defs, blob = data[:idx], data[idx:]

m = re.search(rb"^/ D (\d+) (\d+) (\d+) (\d+)$", defs, re.M)
if not m:
    sys.exit("no '/ D' root entry in pseudofile")
root_time, root_mode, root_uid, root_gid = (g.decode() for g in m.groups())

pat = re.compile(rb"^etc/erlinit\.config R (\d+) (\d+) (\d+) (\d+) \d+ \d+ \d+$", re.M)
m = pat.search(defs)
if not m:
    sys.exit("no 'etc/erlinit.config R' entry in pseudofile")
t, mode, uid, gid = (g.decode() for g in m.groups())
repl = f'etc/erlinit.config F {t} {mode} {uid} {gid} cat "{workdir}/erlinit.patched"'.encode()
defs = pat.sub(repl.replace(b"\\", b"\\\\"), defs, count=1)

open(f"{pf}.patched", "wb").write(defs + blob)
print(f"-root-time {root_time} -root-mode {root_mode} -root-uid {root_uid} -root-gid {root_gid}")
EOF
) || err "failed to patch pseudofile"

mkdir ../empty
mksquashfs ../empty data/rootfs.img -pf ../pseudofile.patched \
    -noappend -no-recovery -no-progress -b "$block_size" -comp "$compression" \
    $root_attrs >/dev/null

# The new superblock must match the original geometry.
unsquashfs -s data/rootfs.img > ../superblock.new
for key in "Block size" "Compression"; do
    old=$(awk -v k="$key" '$0 ~ "^"k {print $NF}' ../superblock.orig)
    new=$(awk -v k="$key" '$0 ~ "^"k {print $NF}' ../superblock.new)
    [[ "$old" == "$new" ]] || err "$key changed: $old -> $new"
done

echo "==> Updating meta.conf (length + blake2b-256 of rootfs.img)"
python3 - data/rootfs.img meta.conf <<'EOF'
import hashlib, re, sys

img, meta = sys.argv[1], sys.argv[2]
data = open(img, "rb").read()
digest = hashlib.blake2b(data, digest_size=32).hexdigest()

text = open(meta).read()
pattern = re.compile(
    r'(file-resource "rootfs\.img" \{\nlength=)\d+(\nblake2b-256=")[0-9a-f]{64}(")'
)
new_text, n = pattern.subn(rf'\g<1>{len(data)}\g<2>{digest}\g<3>', text)
if n != 1:
    sys.exit(f"expected exactly one rootfs.img stanza in {meta}, found {n}")
open(meta, "w").write(new_text)
print(f"    length={len(data)}")
print(f"    blake2b-256={digest}")
EOF

echo "==> Repacking $(basename "$output_fw")"
rm -f "$output_fw"
# Re-zip in the original entry order; fwup streams the archive, so meta.conf
# must come first. -X: no platform extra fields, matching fwup's own output.
zip -q -X "$output_fw" $(cat ../entries.txt)

echo "==> Verifying"
fwup -m -i "$output_fw" >/dev/null || err "fwup cannot parse the patched archive"

mkdir ../verify
cd ../verify
unzip -q "$output_fw" data/rootfs.img
unsquashfs -n -q -d check data/rootfs.img etc/erlinit.config >/dev/null 2>&1
grep -qx -- "-n phyboard-pollux-${SERIAL}" check/etc/erlinit.config \
    || err "patched rootfs does not contain '-n phyboard-pollux-${SERIAL}'"

unsquashfs -n -ll data/rootfs.img | grep 'squashfs-root' > ../listing.new
[[ "$(wc -l < ../listing.orig)" -eq "$(wc -l < ../listing.new)" ]] \
    || err "entry count differs between original and patched rootfs"
# Directory inode sizes depend on how mksquashfs packs the directory tables,
# so blank the size column on directory lines before comparing. Everything
# else (perms, owner, size, mtime, path) must match except erlinit.config.
normalize() { awk '/^d/ {$3="-"} {print}' "$1"; }
stray=$(diff <(normalize ../listing.orig) <(normalize ../listing.new) \
    | grep '^[<>]' | grep -cv 'etc/erlinit\.config' || true)
[[ "$stray" -eq 0 ]] || {
    diff <(normalize ../listing.orig) <(normalize ../listing.new) >&2 || true
    err "more than just etc/erlinit.config differs between original and patched rootfs"
}

echo
echo "OK: $output_fw"
echo "    hostname line: -n phyboard-pollux-${SERIAL}"
echo "    only etc/erlinit.config differs from the original rootfs"
