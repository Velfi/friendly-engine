---
name: vendor-luajit
description: Vendor or refresh the official LuaJIT source tree for friendly-engine. Use when a user asks to download LuaJIT, update third_party/luajit, add or repair the LuaJIT embedded scripting dependency, verify LuaJIT provenance, or repeat the LuaJIT vendoring workflow for contributors.
---

# Vendor LuaJIT

## Workflow

Use the official LuaJIT source repository, not release tarballs. LuaJIT is a
rolling source-only project; the upstream download page says to clone
`https://luajit.org/git/luajit.git` and avoid third-party tarballs or
pseudo-releases.

1. Search or open `https://luajit.org/download.html` to confirm the current
   upstream guidance.
2. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-luajit/scripts/vendor_luajit.zig -- --replace
```

3. Read `third_party/luajit/FRIENDLY_ENGINE_VENDORING.md` and confirm the
   recorded branch and commit.
4. Run:

```sh
zig build test
zig build run-tools -- describe
```

5. Confirm `gem.luajit`, `luajit.describe`, and `luajit.eval` still appear in
   the describe output.

Optional source build check, using a temporary copy so build outputs are not
left under `third_party/luajit`:

```sh
zig run .agents/skills/vendor-luajit/scripts/vendor_luajit.zig -- \
  --source /path/to/luajit-checkout \
  --target /tmp/friendly-engine-luajit-test-vendor \
  --replace
MACOSX_DEPLOYMENT_TARGET=15.0 make -C /tmp/friendly-engine-luajit-test-vendor
```

On macOS, set `MACOSX_DEPLOYMENT_TARGET` to a value supported by the local
toolchain. LuaJIT documents this as required. Without `.git` metadata, LuaJIT
may warn that it cannot determine the rolling release version; keep the exact
source commit in `FRIENDLY_ENGINE_VENDORING.md`.

## Script Options

Use `--source <path>` when a LuaJIT checkout has already been cloned and should
be copied without network access:

```sh
zig run .agents/skills/vendor-luajit/scripts/vendor_luajit.zig -- \
  --source /path/to/luajit \
  --replace
```

Use `--repo` and `--branch` only when upstream changes the canonical location or
branch. Keep the default branch as `v2.1` unless the official LuaJIT download or
status pages say otherwise.

## Guardrails

- Keep `COPYRIGHT`, `README`, `Makefile`, `doc/`, `dynasm/`, `etc/`, and `src/`.
- Do not commit LuaJIT `.git` metadata or local build outputs.
- Do not use GitHub-generated source archives as the source of truth; GitHub is
  only a mirror.
- Do not silently skip a missing source file. The script should fail loudly.
