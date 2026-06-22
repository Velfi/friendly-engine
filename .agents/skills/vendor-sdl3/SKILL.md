---
name: vendor-sdl3
description: Vendor or refresh the SDL3 Zig package for friendly-engine. Use when a user asks to vendor SDL3, update third_party/sdl3, repair the SDL dependency, verify SDL provenance, or repeat the SDL3 vendoring workflow for contributors.
---

# Vendor SDL3

## Workflow

friendly-engine links SDL3 through the Zig package that exposes an `SDL3`
artifact. Keep that package shape intact; do not replace it with an unrelated
upstream SDL checkout unless `build.zig` is changed at the same time.

1. Check `build.zig.zon` for the current `.sdl` dependency source and package
   hash. The default script values mirror the checked-in dependency.
2. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-sdl3/scripts/vendor_sdl3.zig -- --replace
```

3. Confirm `build.zig.zon` points `.sdl` at the local path:

```zig
.sdl = .{
    .path = "third_party/sdl3",
},
```

4. Confirm `third_party/sdl3/build.zig.zon` points `sdl_linux_deps` at the
   local `../sdl_linux_deps` path.
5. Read `third_party/sdl3/FRIENDLY_ENGINE_VENDORING.md` and
   `third_party/sdl_linux_deps/FRIENDLY_ENGINE_VENDORING.md`, then confirm the
   recorded source, branch, revision, and package hashes.
6. Run:

```sh
zig build run-tools -- describe
zig build test
```

## Script Options

Use `--source <path>` when the SDL Zig package already exists locally and should
be copied without network access:

```sh
zig run .agents/skills/vendor-sdl3/scripts/vendor_sdl3.zig -- \
  --source zig-pkg/sdl-0.5.1+3.4.10-SDL--kbMpgGMXke11Ujh5HUPKch7G_SUAS12LI0QFoqj \
  --replace
```

Use `--clone` only when the package is not already present locally or when
refreshing from the upstream package repository:

```sh
zig run .agents/skills/vendor-sdl3/scripts/vendor_sdl3.zig -- \
  --clone \
  --replace
```

Update `--revision` and `--hash` together when changing the SDL package version.

## Guardrails

- Keep `build.zig`, `build.zig.zon`, `include/`, `src/`, `LICENSES/`,
  `LICENSE.txt`, and `REUSE.toml`.
- Do not commit SDL `.git` metadata or local build outputs.
- Do not silently skip missing source files. The script should fail loudly.
- Keep `build.zig.zon` pointed at `third_party/sdl3` after vendoring.
- Keep SDL3's lazy Linux dependency pointed at `../sdl_linux_deps` so Linux
  builds do not fetch a remote package.
