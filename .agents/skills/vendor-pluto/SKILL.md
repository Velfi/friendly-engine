---
name: vendor-pluto
description: Vendor or refresh Pluto SVG/VG source for friendly-engine. Use when a user asks to update third_party/pluto, refresh plutosvg or plutovg, verify Pluto provenance, preserve or repair the SVG bridge, or repeat the Pluto vendoring workflow for contributors.
---

# Vendor Pluto

## Workflow

friendly-engine vendors `plutosvg`, `plutovg`, and a local
`fe_plutosvg_bridge.*` shim. Preserve the bridge files; they are local
integration code.

1. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-pluto/scripts/vendor_pluto.zig -- --replace
```

2. Confirm `third_party/pluto/FRIENDLY_ENGINE_VENDORING.md` records the source.
3. Run:

```sh
zig build test
```

## Script Options

Use `--source <path>` when refreshed `plutosvg/` and `plutovg/` directories are
available locally. Use `--bridge-source <path>` if preserving bridge files from
somewhere other than `third_party/pluto`.

## Guardrails

- Keep `plutosvg/`, `plutovg/`, `fe_plutosvg_bridge.c`, and
  `fe_plutosvg_bridge.h`.
- Do not commit `.git` metadata or local build outputs.
- Do not overwrite or drop the bridge files while refreshing upstream source.
