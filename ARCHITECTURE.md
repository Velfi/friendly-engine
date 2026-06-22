# Friendly Engine Architecture

This document defines a practical architecture for `friendly-engine`, inspired by the Open 3D Engine key concepts.

## 1) Design Principles

- **Modular core first**: keep foundational systems small, stable, and reusable.
- **Feature composition**: ship features as optional modules instead of hard-wiring everything.
- **Event-driven communication**: prefer message passing over direct coupling.
- **Data-oriented runtime**: represent game objects as entities + components.
- **Deterministic content pipeline**: transform source assets into runtime assets ahead of execution.
- **Multi-runtime target**: support both client and headless server builds from one codebase.

## 2) High-Level Layers

1. **Core SDK layer**
   - Math, memory utilities, IDs, serialization, diagnostics, time, jobs.
   - No gameplay dependencies.
2. **Framework layer**
   - ECS world, scene lifecycle, asset system, input abstraction, render abstraction, networking abstraction.
3. **Feature modules ("Gems" model)**
   - Optional packages for rendering backends, physics, AI, UI, audio, tooling.
   - Modules declare dependencies and register services at startup.
   - Current built-in gems in `src/modules/`: `physics3d`, `core_ui`.
4. **Project/game layer**
   - Game rules, content config, startup profile, and entry points for runtimes.

## 3) Repository Layout

```text
friendly-engine/
  build.zig
  engine.kdl               # project config (enabled modules, startup scene/world/bundle)
  scenes/                  # editor/runtime scene JSON
  src/
    root.zig                 # engine library entry (friendly_engine module)
    core/                    # math, ids, buses, time, serialization
    framework/               # ECS world, scene, assets, render, input, network
    modules/
      physics3d/             # built-in gem: rigid-body physics
      core_ui/               # built-in gem: immediate-mode UI context
    runtime/
      bootstrap.zig          # shared runtime boot (config + module graph)
      client/                # game client executable
      editor/                # editor executable
      server/                # headless server executable
      shared/                # geometry, scene I/O, GPU/software viewport
    game/                    # default gameplay hooks and scene spawn
    tools/                   # asset pipeline + describe + modcheck CLIs
  assets/
    source/
    cache/
    bundles/
  docs/
    CODEMAP.md               # one-line-per-module map for LLM navigation
    schema/                  # JSON schemas for generated/interchange files
```

## 4) Module System (O3DE Gem Analogue)

Each module should expose:

- `pub fn register(registry: *ServiceRegistry) !void`
- `pub fn start(world: *World) !void`
- `pub fn stop(world: *World) void`

The engine boot process reads `engine.kdl`, validates enabled module dependencies, then loads modules in topological order.

## 5) Messaging Model (EBus Analogue)

Provide two bus styles:

- **Request bus**: targeted request/response (`Input.GetActionState`, `Asset.Load`).
- **Notification bus**: publish/subscribe events (`EntitySpawned`, `LevelLoaded`).

Rules:

- Prefer interfaces/events over cross-module direct calls.
- Allow queued delivery for cross-thread safety.
- Keep event payloads versioned and serializable for tooling.

## 6) ECS Model

- **Entity**: opaque ID only.
- **Component**: plain data attached to entities.
- **System**: stateless logic that reads/writes component sets.
- **Prefab**: reusable template of entities/components.
- **Spawnable**: runtime-instantiated prefab configured for dynamic objects.

Update order:

1. Input
2. Simulation (gameplay/physics/AI)
3. Animation
4. Rendering submission
5. Late events/cleanup

Physics ownership:

- Authored gameplay data declares physics through `game.physics_body` metadata instead of making every renderable object physical.
- The game physics bridge owns runtime body IDs and keeps them bound to ECS entities incrementally.
- Dynamic bodies are simulation-authoritative and write positions back to `game.scene_transform`.
- Static and kinematic bodies are transform-authoritative and update their physics bodies from authored transforms.
- The first solver pass resolves sphere/AABB contacts with penetration correction and normal impulses; friction, sleeping, and continuous collision detection are later extensions.
- The framework layer does not depend on `gem.physics3d`; physics remains an optional module.

## 7) Asset Pipeline

Asset flow mirrors O3DE's source-to-product model:

1. Author files in `assets/source/`.
2. Asset processor imports and converts to platform/runtime formats.
3. Processed outputs are written into `assets/cache/`.
4. Bundler emits release bundles in `assets/bundles/`.

Requirements:

- Incremental rebuilds by content hash.
- Explicit dependency graph (material -> textures, prefab -> meshes, etc.).
- Target-aware processing (debug/release/platform variants).

## 8) Scripting Strategy

Two tracks:

- **Visual/gameplay graph layer** (future editor integration).
- **Text scripting layer** (Lua/Wren/etc.) for fast gameplay iteration.

Scripts should call engine APIs through bus interfaces, not direct internals.

## 9) Runtime Targets

- **Client runtime**: rendering, audio, input, UI, local simulation.
- **Dedicated server runtime**: no rendering/audio; networking + simulation only.

Both runtimes share core modules, ECS logic, asset metadata, and project code where possible.

## 10) First Milestone

1. Implement `core` and `framework` skeletons.
2. Add module registry and dependency resolver.
3. Add minimal ECS world with one update loop.
4. Add event bus (request + notification).
5. Add basic asset import/cache/bundle CLI pipeline.
6. Split executable targets: `client` and `server`.

## 11) World Model

World geometry and simulation data are organized as **layered authoring** that compiles into streamable **WorldCell** chunks. Authoring layers (terrain, splines, scatter, modular POIs, parametric buildings, sector interiors, local CSG) each produce cell-local outputs; a world compiler merges them into baked runtime products.

See [docs/WORLD.md](docs/WORLD.md) for the canonical world design, compilation pipeline, visibility model, and phased implementation plan.

Relationship to other sections:

- **§6 ECS**: prefabs and spawnables compose entities inside loaded cells; cell streaming activates and deactivates entity batches.
- **§7 Asset pipeline**: per-cell `.fcell` baked outputs join `.fscene`, `.fmesh`, and `.rgba` as cache products under `assets/cache/<target>/`.
- **§8 Scripting**: gameplay scripts interact with loaded cells through request/notification buses, not authoring-layer internals.
