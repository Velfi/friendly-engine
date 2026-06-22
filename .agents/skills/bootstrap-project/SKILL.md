---
name: bootstrap-project
description: Bootstrap a fresh Friendly Engine checkout after cloning or syncing. Use when the repo needs first-run setup: build Zig dependencies, regenerate checked-in schemas, import/bundle/bake assets, and run the standard verification commands before work starts.
---

# Bootstrap Project

Use this skill for a fresh clone, a cleaned workspace, or any checkout where the generated outputs may be stale. The goal is to make the repository ready for normal engine work without hiding failures.

## Workflow

1. Start from the repository root.
2. Build the workspace once with `zig build`.
3. Regenerate checked-in schema files with `zig build run-tools -- write-schemas`.
4. Refresh baked assets and scene/world outputs with `zig build bake`.
5. Run the standard smoke checks.
6. Stop at the first real failure and fix it before moving on.

## Command Map

Use the umbrella command first when you want the normal first-clone path:

```sh
zig build bake
```

Use the individual stages when you need a narrower rebuild:

```sh
zig build run-tools -- import
zig build run-tools -- bundle
zig build run-tools -- bake-scene
zig build run-tools -- world-bake
zig build run-tools -- write-schemas
```

- `import` scans `assets/source/` and converts source assets into cache outputs.
- `bundle` packs imported assets into `assets/bundles/<target>/bundle.json`.
- `bake-scene` refreshes the monolithic scene bake for a chosen scene.
- `world-bake` writes per-cell `.fcell` outputs from the world manifest.
- `write-schemas` regenerates `docs/schema/scene.schema.json` and `docs/schema/world.schema.json`.

## Verification

Run the repository's standard surface checks after bootstrapping:

```sh
zig build run-tools -- help
zig build run-tools -- describe
zig build test
zig build check
zig build run-client -- --headless --frames 3
zig build run-editor -- --software --frames 5
```

If the user only needs a quick sanity pass, `zig build run-tools -- describe` and `zig build test` are the first two checks to run. If viewport rendering matters, prefer the software editor path when GPU availability is uncertain.

The current repository baseline documents known `zig build test` and `zig build check` failures. Run them anyway to capture the present state, then report the first concrete failure instead of treating the checkout as fully bootstrapped.

## Guardrails

- Do not invent fallback setup steps.
- Do not silently skip a missing dependency, schema file, or baked artifact.
- Treat `assets/cache/`, `assets/bundles/`, `.zig-cache/`, and `zig-out/` as generated outputs.
- Leave authored project data alone unless the user explicitly asked to edit it.
- If a command fails, report the first concrete failure and stop there.
