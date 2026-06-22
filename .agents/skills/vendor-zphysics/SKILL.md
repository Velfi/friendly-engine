---
name: vendor-zphysics
description: Vendor or refresh the zphysics Zig package for friendly-engine. Use when a user asks to update third_party/zphysics, refresh zphysics/Jolt physics, verify zphysics provenance, repair the vendored physics dependency, or repeat the zphysics vendoring workflow for contributors.
---

# Vendor zphysics

## Workflow

friendly-engine uses zphysics as a local Zig package through `build.zig.zon`.

1. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-zphysics/scripts/vendor_zphysics.zig -- --replace
```

2. Confirm `build.zig.zon` still points `.zphysics` at `third_party/zphysics`.
3. Read `third_party/zphysics/FRIENDLY_ENGINE_VENDORING.md` and confirm the
   recorded source and package hash.
4. Run:

```sh
zig build test
```

## Script Options

Use `--source <path>` when a newer zphysics package is already available
locally. Use `--package-hash` and `--source-note` when changing the upstream
version or package identity.

## Guardrails

- Keep `build.zig`, `build.zig.zon`, `src/`, `libs/`, `README.md`, and
  `LICENSE`.
- Do not commit `.git` metadata or local build outputs.
- Do not silently skip missing source files. The script should fail loudly.
