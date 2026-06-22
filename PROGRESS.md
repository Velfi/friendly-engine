# Friendly Engine Progress

Last updated: 2026-06-22 (documentation audit)

This file tracks implementation status against `AGENTS.md` goals and `ARCHITECTURE.md` milestone items.

## Current Snapshot

- [x] Milestone 1 foundation is implemented (core/framework skeleton, module graph, runtime targets)
- [x] Runtime loop + world tick path is implemented in both `client` and `server`
- [x] Request bus API is implemented (`register`, `unregister`, `request`) with unit test coverage
- [x] Tools pipeline CLI is implemented (`friendly_engine_tools import|bundle|bake-scene|world-bake|terrain|bake|describe|assets.describe|write-schemas`)
- [~] End-user 3D runtime: SDL3 client window with production GPU renderer (SDL3 GPU API -> Metal/Vulkan/D3D12), explicit software mode with diffuse lighting, volumetric distance fog (4-slice exponential integration with height falloff) from baked `atmosphere.settings` blobs on world-streamed cells, and project scene load; ECS scene spawn drives render commands via `draw_mesh`; directional shadow maps and scene light objects feed the lit shader; authored physics bodies sync incrementally with `gem.physics3d`
- [x] Editor shell: SDL3 project manager + project editor with viewport, scene save/load, undo, snap grid, numeric property fields, transform gizmos
- [~] Five-mode editor UI (World, Layout, Architecture, Prop, Life): mode tabs, tool bars, left/right inspectors, bottom strip, and Life timeline are wired; curves editor, full bone posing, and play-in-editor remain stubs

## Goal Progress (AGENTS.md)

- [~] Cross-platform 3D games (Stage 1: Mac/Linux/Windows)
  - Estimated progress: 66%
  - Done: runtime targets, module dependency resolver, runtime/world tick path, request+notification buses, asset import/bundle CLI, SDL3 client window, **production GPU backend abstraction** (`runtime/shared/gpu_api.zig`) with SDL3 GPU API path (Metal on macOS, Vulkan on Linux, D3D12 on Windows), mesh/texture upload and lit textured shaders with directional + point lights, directional shadow maps, and volumetric distance fog (4-slice exponential integration with height falloff) from baked `atmosphere.settings` cell blobs, explicit software rasterizer mode with matching diffuse lighting and fog, runtime bundle loader (`framework/bundle_loader.zig`) with `engine.kdl` `startup_bundle` and scene texture resolution, project scene load from `engine.kdl` startup path, starter scene creation for new projects, ECS scene spawn with transform/drawable/physics components and `draw_mesh` render queue, framework prefab/spawnable registry MVP, incremental physics sync with dynamic/static/kinematic body intent and explicit transform authority, positional collision correction, friction, sleeping, continuous collision detection, normal-impulse response for sphere/AABB bodies, scene/editor authoring for basic static/dynamic/kinematic physics body metadata
  - Missing: DX12 Windows validation, Linux Vulkan validation, richer gameplay loop examples, mobile Stage 2
- [ ] Cross-platform 3D games (Stage 2: iOS/Android)
  - Estimated progress: 0%
  - Missing: mobile runtime targets and platform integration
- [~] Fast level blocking and texturing workflow (TrenchBroom-like)
  - Estimated progress: 78%
  - Done: editor viewport with orbit/pan camera, primitive placement, Blockout brush (add/subtract boxes, ramp, doorway, stair), face drag resize with numeric dimension feedback, blockout intent in scene KDL, local CSG layer persistence, generated-solid CSG union/subtract for boxes, wedges, and convex prisms, undo/redo for blockout edits, texture fit/align/rotate/scale with world-unit scale, per-face materials, material error strip, grid snap and brush size feedback
  - Missing: face extrude, production node materials, editor-facing prefab workflow, broader CSG authoring controls
- [~] Editor editable by the editor
  - Estimated progress: 82%
  - Done: `core_ui` foundation, command palette (Cmd/Ctrl+P), UI tree inspector summary, editor command catalog in `describe`, world dirty-cell bake/reload workflow, gameplay component fields in inspector, physics validation with specific errors
  - Missing: in-editor module authoring, visual UI copy editor file workflow polish

## First Milestone Status (ARCHITECTURE.md section 10)

- [x] 1) Implement `core` and `framework` skeletons
- [x] 2) Add module registry and dependency resolver
- [x] 3) Add minimal ECS world with one update loop
- [x] 4) Add event bus (request + notification)
- [x] 5) Add basic asset import/cache/bundle CLI pipeline
- [x] 6) Split executable targets: `client` and `server`

Legend: `[x]` done, `[~]` in progress, `[ ]` not started

## Five-Mode Editor UI

- **World** — terrain authoring (paint, splat preview, LOD clipmap, auto-bake, collision preview); scatter tool MVP (seed rules, exclusion zones, density-mask brush with preview overlay, debounced bake); roads/splines MVP (v2 road graph placement, drag segment, terrain deformation, mesh preview); atmosphere tool MVP (sky sun/moon, project default + per-cell fog banks in `layers/atmosphere.kdl`, cell-scoped fog inspector, live viewport preview with volumetric fog matching client, debounced cell/world bake, runtime client fog from active camera cell's baked `atmosphere.settings`)
- **Layout** — object select/move/rotate/scale, transform gizmos, scene hierarchy, snap grid
- **Architecture** — blockout brush (add/subtract), ramp/doorway/stair placement, face resize, texture paint tool
- **Prop** — prefab placement, mesh edit pick, per-face material paint
- **Life** — animation clips/tracks/timeline, pose tool with auto-key, per-channel keyframes, interpolation (linear/ease in/out/hold), named pose library (rest + save); curves editor and full skeletal posing stubbed


Run these on each status check:

```sh
zig build test
zig build check
zig build run-tools -- describe
zig build run-client -- --headless --frames 3
zig build run-client -- --frames 120          # windowed; GPU required (SDL3 GPU -> Metal/Vulkan/D3D12)
zig build run-client -- --software --frames 120
zig build run-server
zig build run-editor -- --frames 5
zig build run-editor -- --software --frames 5
zig build run-tools -- help
```

Expected today:

- `zig build test` currently fails on scene KDL marker round trips and prop asset document/shape-intent round trips; it should return to 0 before the next green milestone is recorded
- `zig build check` currently fails fast on the known source-size budget debt listed in `zig build modcheck`; it should return to printing `check ok: LLM-friendly surface passes size budget and schema files exist` after those modules are split
- `zig build run-tools -- describe` prints JSON listing runtime targets, modules, components, and request commands
- `zig build run-client -- --headless --frames 3` prints scene summary and `friendly-engine client runtime initialized`
- Windowed client prints `friendly-engine client: Metal GPU renderer enabled (SDL3 GPU API)` or `Vulkan ...` / `D3D12 ...`; GPU init failure exits unless `--software` is passed
- `zig build run-client -- --software --frames 120` prints `software renderer enabled`
- `zig build run-server` prints `friendly-engine dedicated server runtime initialized`
- `zig build run-editor -- --frames 5` opens an editor window and prints `friendly-engine editor runtime initialized (...)`; when GPU init succeeds also prints `friendly-engine editor: Metal GPU viewport enabled (SDL3 GPU API)` (or Vulkan/D3D12)
- `zig build run-editor -- --software --frames 5` prints `friendly-engine editor: software viewport renderer enabled`

## Platform Validation Checklist

Use [docs/PLATFORM_VALIDATION.md](docs/PLATFORM_VALIDATION.md) for Stage 1
macOS Metal, Linux Vulkan, and Windows D3D12 validation. Record dated platform
results under `Latest review`; Linux and Windows are not verified until the
checklist commands are run on those platforms.

Latest review (2026-06-22 documentation audit):

- Verified: `zig build`
- Verified: `zig build run-tools -- help`
- Verified: `zig build run-tools -- describe`
- Verified: Markdown local links after this audit
- Failed: `zig build test` completed 531/542 passing tests; failures are concentrated in `scene_kdl` marker round trips, `prop_asset_doc` empty tags/shape-intent parsing, and prop editor tests that reopen persisted shape intent
- Failed as expected for current size-budget debt: `zig build check` reports 31 oversized source modules, led by `src/runtime/editor/editor_commands.zig`, `src/runtime/editor/project_editor_ui_world.zig`, `src/runtime/editor/project_editor_prop_asset.zig`, `src/runtime/editor/project_editor_blockout.zig`, and `src/runtime/editor/project_editor_ui_prop.zig`
- Failed as expected for the same reason: `zig build modcheck`
- Not rerun in this audit: windowed GPU client/editor commands, headless client, and server

Latest review (2026-06-15 roadmap batch B–G):

- Verified: `zig build test` (blockout intent, texture transforms, physics validation, gameplay, wireframe commands, world cell describe)
- Verified: `zig build check`
- Verified: `zig build run-tools -- describe` (doorway/stair, command palette, bake dirty, texture, gameplay commands)
- Verified: `zig build run-client -- --headless --frames 3`
- Verified: `zig build run-editor -- --software --frames 5`
- Platform validation: macOS Metal windowed client/editor not rerun in this batch; Linux Vulkan and Windows D3D12 await host runs per [docs/PLATFORM_VALIDATION.md](docs/PLATFORM_VALIDATION.md)
- Mobile Stage 2: scaffolding documented in [docs/MOBILE_STAGE2.md](docs/MOBILE_STAGE2.md); no device targets yet

Latest review (2026-06-15):

- Verified: `zig build test`
- Verified: `zig build test` after parallel roadmap slices B1/E1/G1
- Verified: `zig build test` after parallel roadmap slices D1/C1/F1 and shared editor command ID generator
- Verified: WORLD manifest schema/docs refreshed against current MVP world implementation
- Verified: `zig build check`
- Verified: `zig build check` after parallel roadmap slices B1/E1/G1
- Verified: `zig build check` after parallel roadmap slices D1/C1/F1 and shared editor command ID generator
- Verified: `zig build run-tools -- describe`
- Verified: `zig build run-tools -- describe` lists `editor_commands`, generated material command IDs, and editor screen sections
- Verified: `zig build run-client -- --headless --frames 3`
- Verified: `zig build run-client -- --software --frames 3`
- Verified: `zig build run-server`
- Verified: `zig build run-tools -- help`
- Not rerun in this review: windowed GPU client/editor commands, because they require opening GUI windows

## Next Work

See [docs/ROADMAP.md](docs/ROADMAP.md) for the current parallel workstreams. Platform
validation (A1/A2) and the second batch of editor/renderer/world slices are the
ready lanes.

## Runtime Asset Bundles (MVP)

- Format: tools output `assets/bundles/<target>/bundle.json` (`schema_version` 1) with artifact paths into `assets/cache/`
- Module: `src/framework/bundle_loader.zig` — parse bundle, resolve refs by dependency basename, read artifact bytes, register with `AssetSystem`
- Client wiring: `engine.kdl` `startup_bundle`; configured bundles are required at startup, and `startup_bundle=""` means use project scene texture files directly
- Test: `runtime bundle load round trip reads artifacts` in `bundle_loader.zig`

## GPU Render Backend (MVP)

- **Production path**: SDL3 GPU API (`runtime/shared/gpu_backend_sdl.zig` + `sdl_gpu.zig`) — Metal on macOS, Vulkan on Linux, D3D12 on Windows; precompiled shaders embedded per platform (`runtime/shared/shaders/`)
- **Lighting**: `runtime/shared/render_lighting.zig` gathers sun + point lights; lit mesh pipeline uses vertex normals, ambient + Lambert diffuse, directional shadow maps (`cast_shadows` / `receive_shadows` honored), and volumetric distance fog from baked `atmosphere.settings` blobs (`fog_math.zig`, `render_fog.zig`, `TexturedQuadLit.frag.wgsl` — 4-slice exponential integration with height-based density falloff); scatter prototype meshes batch into per-mesh GPU instanced draws via `TexturedQuadInstanced.vert`, `gpu_instance_buffer.zig`, and `render_commands.appendInstancedMesh`
- **Abstraction**: `runtime/shared/gpu_api.zig` — `GpuBackendKind` (`.sdl_gpu` only), unified `GpuRenderer` facade behind `framework/render.zig` command queue
- **Software mode**: software rasterizer (`SceneView`) applies the same diffuse lighting and volumetric fog model when `--software` is passed
- Client wiring: `desktop_backend.zig` requires SDL3 GPU unless `--software` is passed
- Editor wiring: `editor_viewport_gpu.zig` uses SDL3 GPU offscreen (Metal/Vulkan/D3D12); readback pixels feed software overlays then SDL texture blit; `--software` selects the software viewport
- CLI: `--gpu` (require SDL3 GPU, default), `--software`, `--headless` skips window/GPU entirely
- Link flags: `build.zig` links Metal+QuartzCore (macOS), Vulkan (Linux)
- Renderer command prep: `runtime/shared/render_commands.zig` provides sorted command buffers, pass/layer/material sort keys, stats, and tests.

## Remaining Stubs

- GPU backend: spot-light cones, cascaded shadow maps, per-instance scatter fade alpha in the lit shader, and material batching via sort keys; runtime mesh hot-reload beyond scene object count change still deferred
- Physics: no rotation/angular velocity or compound bodies; basic static/dynamic/kinematic body metadata is authored in scene files and the inspector
- Framework: `jobs.zig`, `input.zig`, and `network.zig` are useful abstractions with tests, but still minimal backend surfaces rather than production systems

## Layered World ([docs/WORLD.md](docs/WORLD.md))

Architecture documented; runtime cell streaming and compiler skeleton are implemented. Phase 2-6 modules have MVP compiler outputs, strict layer parsing, retained baked metadata, targeted cell bake, synchronous `.fcell` IO, and runtime cell describe/reload requests, but the authoring workflows called out in [docs/WORLD.md](docs/WORLD.md) are not complete yet. See [ARCHITECTURE.md](ARCHITECTURE.md) §11.

- [x] Phase 1: Runtime chunk system (`WorldCell`, `world.kdl`, `.fcell`, streaming manager)
- [~] Phase 2: Terrain and splines (terrain editor MVP complete; roads tool MVP: viewport click/drag, v2 `layers/splines.kdl` road graph upsert, terrain height/splat deformation, live road mesh preview, debounced bake; atmosphere editor MVP with project-level `layers/atmosphere.kdl`, sky/fog inspector controls, and world-wide dirty-cell bake; baked road collision strips load into static Jolt bodies at runtime with fcell reload sync; production Jolt heightfield terrain collision loads from `terrain.heightfield` blobs with fcell round-trip and fail-fast when blob missing)
- [~] Phase 3: Sector interiors (MVP meshes/blobs exist; room authoring, portals, and visibility workflow are not complete)
- [~] Phase 4: Parametric buildings (MVP generated meshes exist; semantic building authoring is not complete)
- [~] Phase 5: Scatter system (editor MVP: rule seeding, exclusion zones, density-mask brush with preview overlay, debounced bake; runtime loads baked `scatter.clusters` / `scatter.cluster_meta` blobs from streamed `.fcell` cells, groups visible scatter draw batches by prototype mesh in `scatter_instancing.zig`, submits GPU instanced draw calls per mesh on the SDL3 GPU path while preserving `scatter_cull` fade/cull filtering via scaled instance transforms, and keeps software rendering per-object via `SceneView`)
- [~] Phase 6: Local CSG-like tools (semantic doorway compiler, editor blockout persistence, and generated-solid box/wedge/prism union-subtract exist; broader editor CSG controls are still incomplete)
