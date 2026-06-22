# Friendly Engine Codemap

One-line map of every module. Read this before editing source.

## Conventions

- Every `mod.zig` exports its subsystem and includes unit tests.
- Module gems expose `register`, `start`, `stop` and are listed in `src/modules/mod.zig` `builtin_modules`.
- IDs and buses live in `src/core/`; gameplay uses `framework.World`.
- Runtime boot goes through `src/runtime/bootstrap.zig` (do not duplicate in `main.zig`).
- Introspection: `zig build run-tools -- describe` emits engine JSON; request bus serves `world.*` commands at runtime.
- File size budget: `zig build check` and `zig build modcheck` fail when any `.zig` file under `src/` exceeds 700 lines.
- Project repair diagnostics: `zig build doctor -- --project path` checks project KDL files and references in one LLM-friendly report.

## Entry Points

| File | Role |
|------|------|
| [src/root.zig](../src/root.zig) | `friendly_engine` library: `init`, `EngineConfig`, re-exports |
| [src/runtime/client/main.zig](../src/runtime/client/main.zig) | Client executable |
| [src/runtime/editor/main.zig](../src/runtime/editor/main.zig) | Editor executable |
| [src/runtime/server/main.zig](../src/runtime/server/main.zig) | Headless server executable |
| [src/tools/main.zig](../src/tools/main.zig) | Tools CLI (`import`, `bundle`, `describe`) |
| [src/tools/doctor_main.zig](../src/tools/doctor_main.zig) | `doctor` project diagnostics CLI behind `zig build doctor` |

## Core (`src/core/`)

| File | Role |
|------|------|
| mod.zig | Re-exports; `NotificationBus`, `RequestBus`, `EventEnvelope` |
| ids.zig | `EntityId`, `AssetId`, `IdGenerator`, string hash |
| math.zig | Vectors, clamp, matrix helpers |
| memory.zig | Allocation helpers |
| serialization.zig | Shared serialize helpers |
| diagnostics.zig | Logging hooks |
| time.zig | `FrameClock`, `FixedStep` |
| jobs.zig | Deterministic job queue and `parallelFor` helper |

## Framework (`src/framework/`)

| File | Role |
|------|------|
| mod.zig | `World`: ECS, buses, scene, assets, input, render, network, component registry |
| ecs.zig | `World`, `ComponentStorage(T)` |
| components.zig | Named component registry and field schemas |
| scene.zig | `SceneManager`, scene lifecycle callbacks |
| assets.zig | `AssetSystem`, path registration |
| prefab.zig | Data-only prefab library and spawnable instantiation |
| input.zig | `InputSystem` backend polling, action states, and route ownership |
| render.zig | `RenderSystem`, command queue |
| network.zig | `NetworkSystem` backend send queue and incoming packet buffer |
| bundle_loader.zig | Runtime bundle JSON load and artifact resolve |
| introspection.zig | `world.describe`, `world.listEntities`, `scene.describe` handlers |

## Modules (`src/modules/`)

| File | Role |
|------|------|
| mod.zig | `ModuleGraph`, `ServiceRegistry`, `builtin_modules` table, project config parse |
| registry.zig | `ServiceRegistry`, `ModuleGraph`, request catalog |
| project_config.zig | `OwnedProjectConfig`, load/parse `engine.kdl` |
| physics3d/mod.zig | Rigid-body physics world gem |
| core_ui/mod.zig | Immediate-mode UI panel/button/label gem |
| terrain/mod.zig | Terrain layer compile: heightfield LODs, splat blobs, heightfield collision |
| terrain/mesh_builder.zig | Shared heightfield mesh LOD build + normals |
| terrain/splat_texture.zig | Splat-driven 128² material blend textures |
| terrain/lod_pick.zig | Distance-based LOD tier selection |
| project_editor_terrain_preview.zig | Editor live terrain preview, clipmap radius, auto-bake |
| splines/mod.zig | Spline layer compile: road meshes, terrain deformation/mask blobs |
| sectors/mod.zig | Sector interior compile: room meshes, occlusion/navmesh blobs |
| buildings/mod.zig | Parametric building compile: shell/interior meshes, portal + LOD blobs |
| scatter/mod.zig | Scatter compile: rule-driven clusters + density-mask overrides |
| local_csg/mod.zig | Local CSG semantic cuts: doorway wall splits and trim generation |

## Game (`src/game/`)

| File | Role |
|------|------|
| mod.zig | `tickClient`, `tickServer`, `registerDefaults`, scene state pointer |
| scene_spawn.zig | ECS spawn from scene objects; `SceneTransform`, `SceneDrawable` |
| physics_types.zig | Authored physics body metadata shared by scene spawn and simulation |
| physics.zig | Scene physics sync, body bindings, and transform authority rules |
| level_scene.zig | Level scene helpers |

## Runtime Shared (`src/runtime/shared/`)

| File | Role |
|------|------|
| mod.zig | Re-exports shared runtime utilities |
| geometry.zig | Primitives, mesh build |
| scene_io.zig | Scene JSON load/save |
| scene_physics.zig | Authored scene physics metadata shared by scene I/O and editor |
| viewport3d.zig | Software 3D rasterizer |
| gpu_api.zig | GPU backend facade |
| gpu_backend_sdl.zig | SDL3 GPU implementation |
| render_commands.zig | Stateless render command buffer, sort keys, and command stats |
| render_visibility.zig | CPU-side scene/cell visibility preparation |
| editor_command_ids.zig | Shared editor command ID constants and generators for UI/describe |
| sdl.zig | SDL3 bindings subset |
| editor_math.zig | Editor vector math |
| color.zig | RGBA color type |

## Runtime Editor (`src/runtime/editor/`)

| File | Role |
|------|------|
| app.zig | Editor SDL app loop, screen switching, core UI host wiring |
| editor_core_ui.zig | Editor `core_ui` host: frame input, build callback, draw bridge |
| editor_core_ui_input.zig | SDL events accumulated into `core_ui.InputState` |
| editor_core_ui_draw.zig | `core_ui.RenderCommand` drawing through SDL renderer + FreeType |
| pm_ui.zig | Project Manager render wrapper using the shared core UI host |
| pm_ui_build.zig | Project Manager screen tree declared as `core_ui` commands |
| pm_state.zig | Project Manager project list, dialogs, config, shortcuts |
| project_editor.zig | Project editor facade |
| project_editor_state.zig | Project editor state, scene load/save, render/input delegation |
| project_editor_dirty_cells.zig | Project editor dirty world-cell diagnostics |
| project_editor_ui_build.zig | Project editor chrome tree declared as `core_ui` commands |
| project_editor_blockout.zig | Blockout brush and semantic ramp authoring helpers |
| project_editor_materials.zig | Editor material catalog and stable material command IDs |
| project_editor_material_apply.zig | Apply/select editor material catalog entries |
| project_editor_physics.zig | Inspector actions for authored physics body metadata |
| project_editor_render.zig | Project editor render orchestration: core UI chrome + custom viewport |
| project_editor_input.zig | Project editor shortcuts, viewport clicks, drag/camera handling |
| project_editor_render_viewport.zig | Custom 3D viewport draw path; intentionally outside `core_ui` |

## Runtime Boot

| File | Role |
|------|------|
| bootstrap.zig | `BootResult`: load config, resolve modules, register/start gems |

## Tools (`src/tools/`)

| File | Role |
|------|------|
| mod.zig | Re-exports tools API |
| assets.zig | `import`, `bundle` CLI |
| describe.zig | `describe` CLI — machine-readable engine catalog |
| module_size.zig | Oversized file scanner enforcing the 700-line source budget |
| modcheck_main.zig | modcheck executable entry |
| doctor_main.zig | Doctor executable: parses project config/world/scene KDL and validates referenced assets |
| schemas.zig | JSON schema document builders for legacy/generated data |

## Docs

| File | Role |
|------|------|
| [docs/ROADMAP.md](ROADMAP.md) | Combined planning front door with parallel workstreams and done criteria |
| [PROGRESS.md](../PROGRESS.md) | Verified milestones and current implementation state |
| [docs/WORLD.md](WORLD.md) | Layered world compiler design, authoring layers, phased plan |
| [docs/UI.md](UI.md) | Canonical editor UI and UX design goals |
| [docs/EDITOR_UI.md](EDITOR_UI.md) | Detailed editor layout, workflows, and interaction model |
| [docs/PROP_MODE_UX.md](PROP_MODE_UX.md) | Prop workshop UX, library management, display/edit modes, painting |
| [docs/UX_SCENARIOS.md](UX_SCENARIOS.md) | Repeatable editor playtest scenarios and run logs |
| [docs/UI_COPY.md](UI_COPY.md) | Editor and tool UI string guidelines |
| [docs/EXTENDING.md](EXTENDING.md) | Add modules, components, requests, and runtime targets |
| docs/schema/scene.schema.json | JSON Schema for scene files |
| docs/schema/world.schema.json | Legacy JSON Schema for old world manifest |

## World (`src/world/`)

Runtime chunk system and layered world compiler are implemented for Phases 1-6 MVP.

| File | Role |
|------|------|
| src/world/cell.zig | `CellId`, `WorldCell` data model |
| src/world/manifest.zig | `world.kdl` manifest load |
| src/world/stream.zig | Cell load/unload by active region |
| src/world/file_io.zig | Synchronous `.fcell` read/write boundary |
| src/world/fcell.zig | `.fcell` baked cell binary codec (`FCEL`) |
| src/world/compiler/mod.zig | Layer merge and cell bake orchestration |
| src/world/compiler/layer.zig | `WorldCompilerLayer` hooks + compile context + blob helpers |
| src/tools/world_bake.zig | CLI: authoring → per-cell `.fcell` |
| src/game/cell_spawn.zig | ECS activation from loaded cells |
| src/framework/world_stream.zig | Optional framework hook for streaming manager |
