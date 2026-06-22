---
name: vendor-xatlas
description: Vendor or refresh the xatlas UV unwrapping source for friendly-engine. Use when a user asks to update third_party/xatlas, refresh xatlas, verify xatlas provenance, repair the xatlas bridge/source drop, or repeat the xatlas vendoring workflow for contributors.
---

# Vendor xatlas

## Workflow

friendly-engine vendors only the xatlas files required by the paint atlas
integration plus a local C ABI bridge. Keep the bridge files; they are not from
upstream.

1. Run the vendoring script from the repository root:

```sh
zig run .agents/skills/vendor-xatlas/scripts/vendor_xatlas.zig -- --replace
```

2. Confirm `third_party/xatlas/README.md` records the upstream repo and commit.
3. Confirm `src/runtime/shared/uv_atlas.zig` uses the same commit string in
   `xatlas_commit`.
4. Run:

```sh
zig build test
```

## Script Options

Use `--source <path>` when an xatlas checkout already exists locally and should
be copied without network access:

```sh
zig run .agents/skills/vendor-xatlas/scripts/vendor_xatlas.zig -- \
  --source /path/to/xatlas \
  --replace
```

Use `--bridge-source <path>` if the bridge files should be preserved from a
directory other than `third_party/xatlas`.

Update `--revision` and `src/runtime/shared/uv_atlas.zig` together when changing
the vendored xatlas commit.

## Guardrails

- Keep only `source/xatlas/xatlas.h`, `source/xatlas/xatlas.cpp`, `LICENSE`,
  `README.md`, `fe_xatlas_bridge.h`, and `fe_xatlas_bridge.cpp`.
- Do not commit xatlas `.git` metadata or local build outputs.
- Do not overwrite or drop the bridge files while refreshing upstream xatlas.
- Do not silently skip missing source files. The script should fail loudly.
