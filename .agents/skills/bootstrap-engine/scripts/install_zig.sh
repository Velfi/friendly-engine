#!/usr/bin/env sh
set -eu

version="${ZIG_VERSION:-0.16.0}"
root="${FRIENDLY_ENGINE_ROOT:-$(pwd)}"
install_root="${ZIG_INSTALL_ROOT:-$root/.agent-tools/zig/$version}"
bin_dir="$install_root/bin"
zig_bin="$bin_dir/zig"

if [ -x "$zig_bin" ] && "$zig_bin" version | grep -Eq "^0\\.16\\."; then
    printf '%s\n' "$zig_bin"
    exit 0
fi

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
    Darwin) zig_os="macos" ;;
    Linux) zig_os="linux" ;;
    *) printf 'unsupported OS for repo-local Zig install: %s\n' "$os" >&2; exit 1 ;;
esac

case "$arch" in
    x86_64|amd64) zig_arch="x86_64" ;;
    arm64|aarch64) zig_arch="aarch64" ;;
    *) printf 'unsupported architecture for repo-local Zig install: %s\n' "$arch" >&2; exit 1 ;;
esac

target="$zig_arch-$zig_os"
tmp_dir="${TMPDIR:-/tmp}/friendly-engine-zig-$version-$$"
index_file="$tmp_dir/index.json"
archive_file="$tmp_dir/zig.tar.xz"

mkdir -p "$tmp_dir" "$bin_dir"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

curl -fsSL "https://ziglang.org/download/index.json" -o "$index_file"

python3 - "$index_file" "$version" "$target" "$archive_file" "$install_root" <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request

index_path, version, target, archive_path, install_root = sys.argv[1:]
with open(index_path, "r", encoding="utf-8") as handle:
    index = json.load(handle)

try:
    artifact = index[version][target]
except KeyError as exc:
    raise SystemExit(f"zig {version} artifact for {target} not found in official index") from exc

tarball = artifact["tarball"]
expected = artifact["shasum"]

urllib.request.urlretrieve(tarball, archive_path)
digest = hashlib.sha256()
with open(archive_path, "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)

actual = digest.hexdigest()
if actual != expected:
    raise SystemExit(f"zig archive shasum mismatch: expected {expected}, got {actual}")

extract_root = install_root + ".extracting"
if os.path.exists(extract_root):
    shutil.rmtree(extract_root)
os.makedirs(extract_root)

with tarfile.open(archive_path, "r:xz") as archive:
    archive.extractall(extract_root)

entries = [name for name in os.listdir(extract_root) if not name.startswith(".")]
if len(entries) != 1:
    raise SystemExit(f"expected one Zig archive root, found {entries}")

payload = os.path.join(extract_root, entries[0])
if os.path.exists(install_root):
    shutil.rmtree(install_root)
shutil.move(payload, install_root)
shutil.rmtree(extract_root)

zig = os.path.join(install_root, "zig")
if os.name != "nt":
    os.chmod(zig, 0o755)

reported = subprocess.check_output([zig, "version"], text=True).strip()
if not reported.startswith("0.16."):
    raise SystemExit(f"installed Zig version {reported}, expected 0.16.x")

bin_dir = os.path.join(install_root, "bin")
os.makedirs(bin_dir, exist_ok=True)
link = os.path.join(bin_dir, "zig")
if os.path.lexists(link):
    os.remove(link)
os.symlink(os.path.join("..", "zig"), link)
print(link)
PY
