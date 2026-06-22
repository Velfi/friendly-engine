---
name: iconoir
description: Download, vendor, and wire Iconoir SVG icons for friendly-engine. Use when a user asks to add new icons, download Iconoir assets, replace text buttons with icons, refresh icon provenance, or update the editor's Iconoir embed mapping.
---

# Iconoir

## Workflow

friendly-engine keeps Iconoir SVGs in two places:

- `assets/source/icons/iconoir/` records source/provenance and `manifest.json`.
- `src/runtime/editor/icons/iconoir/` contains the SVGs embedded by the editor renderer.

Use `scripts/download_iconoir.zig` from the repository root to fetch missing icons:

```sh
zig run .agents/skills/iconoir/scripts/download_iconoir.zig -- cursor-pointer road --alias cursor=cursor-pointer
```

The script:

- Runs under Zig and downloads SVGs from the Iconoir GitHub repository.
- Writes each SVG to both Iconoir directories.
- Updates `assets/source/icons/iconoir/manifest.json`.
- Fails loudly when an icon cannot be fetched or the manifest cannot be parsed.

Network access is required. If sandboxed download attempts fail with DNS or connection errors, rerun with elevated network approval.

## Wiring Icons

After downloading, update `src/runtime/editor/editor_core_ui_draw_icons.zig` so `iconoirSvg` maps semantic names to `@embedFile("icons/iconoir/<file>.svg")`.

Prefer semantic aliases at call sites when they improve readability:

```zig
if (std.mem.eql(u8, icon, "cursor")) return @embedFile("icons/iconoir/cursor-pointer.svg");
```

Keep aliases stable once UI commands use them. Do not silently rely on the fallback drawing path for intended Iconoir icons.

## Verification

Run:

```sh
zig build
zig build test
```

When the change affects visible editor UI, prefer MCP editor control for visual verification:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_describe","arguments":{}}}' | ./zig-out/bin/friendly_engine_mcp
```

Use `screenshot_editor` or `screenshot_viewport` when the running editor can show the affected UI state.
