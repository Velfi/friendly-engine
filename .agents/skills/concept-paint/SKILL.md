---
name: concept-paint
description: Use when working with friendly-engine Concept Paint: capturing editor viewport screenshots for AI/external styling, creating provider request packages, importing styled images, projecting them as stencils, or baking concept paint into terrain, props, architecture plots, or layout-mode unique surfaces through MCP/editor commands.
---

# Concept Paint

Use this skill to operate or extend friendly-engine's Concept Paint workflow. Concept Paint turns a viewport screenshot into an imported styled image, then projects that image from the captured camera and bakes it into editable authoring surfaces.

## Command Flow

1. Capture the current viewport first with MCP `screenshot_viewport`.
2. Start a concept paint session with `concept_paint_capture`, passing the screenshot path from step 1.
3. If an external image tool/provider is needed, call `concept_paint_request_package` after capture. It writes a JSON package under `.friendly-engine/concept-paint/` and fails loudly when `provider` was not supplied.
4. Once a styled PNG/JPEG exists, call `concept_paint_import_styled` with `styled_path`.
5. Inspect readiness with `concept_paint_describe`.
6. Bake the stencil with `concept_paint_apply`.
7. Clear the session with `concept_paint_clear` when finished or before starting over.

Prefer command names through MCP tool aliases when available:

```json
{"name":"screenshot-viewport","id":"concept-shot"}
{"name":"concept-paint.capture","id":"concept-session","screenshot_path":"/absolute/path/from/screenshot_viewport.png","prompt":"painted mossy ruins at dusk","provider":"external","desired_style":"lo-fi hand-painted blockout","opacity":0.85,"blend_mode":"normal"}
{"name":"concept-paint.request-package","id":"concept-package"}
{"name":"concept-paint.import-styled","id":"concept-import","styled_path":"/absolute/or/project/relative/styled.png"}
{"name":"concept-paint.describe","id":"concept-ready"}
{"name":"concept-paint.apply","id":"concept-apply"}
```

## Mode Scopes

Concept Paint resolves targets from the editor mode at capture time:

- World mode: bake into authored terrain splat layers by nearest existing terrain paint color.
- Prop mode: bake into the currently selected/open unique prop asset paint atlas.
- Architecture mode: bake into the currently selected architecture object/plot surface texture atlas.
- Layout mode: bake into terrain and unique scene objects; instanced props are skipped unless they are made unique first.

If there is no editable target in projection, expect `ConceptPaintNoEditableSurfacesInProjection`. Do not paper over this with fallback targets.

## Working Rules

- Do not make the editor call a network image provider directly unless a future provider implementation exists. V1 uses screenshot files, request packages, and imported styled image files.
- Treat `screenshot_path` and `styled_path` as required real PNG/JPEG files. Invalid extensions, missing files, or backslash paths should fail.
- Use `opacity` in `[0,1]` and `blend_mode` as `normal` or `multiply`.
- Preserve the fail-fast behavior: missing session, missing screenshot, missing styled image, missing provider, invalid image, and invalid target should return explicit errors.
- After `concept_paint_apply`, run `screenshot_viewport` plus `editor_describe` or `perf_describe` for visual/state verification when an editor is running.

## Implementation Notes

When modifying the feature, keep the core implementation in `src/runtime/editor/project_editor_concept_paint.zig` under the module-size budget. Update all of these surfaces together when adding commands or fields:

- `src/runtime/shared/editor_control_commands.zig` for MCP schemas and command catalog entries.
- `src/runtime/editor/editor_command_file.zig` for parsed command fields.
- `src/runtime/editor/editor_commands.zig` for dispatch and JSON results.
- `src/runtime/editor/project_editor_types.zig` for session metadata types.
- `src/modules/concept_paint/mod.zig` and `src/modules/mod.zig` for gem registration.

Always verify with `zig build test` and `zig build run-tools -- describe`. If `zig build check` fails only on pre-existing oversized files, report that separately rather than changing unrelated modules.
