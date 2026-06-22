<p align="center">
  <img src="logo.png" alt="Friendly Engine logo" width="180">
</p>

# Friendly Engine

Friendly Engine is an early-stage 3D game engine and editor focused on fast level blocking, simple texturing, and LLM-friendly tooling. The goal is to make building simple 3D games feel direct: block out spaces quickly, give them readable materials, inspect the project through clear data, and let agents safely help with repetitive editor work.

The editor is built with the same framework used by games made in the engine, so the editor itself is meant to become editable and extensible from inside Friendly Engine.

## What Works Today

- Desktop runtime targets for client, editor, server, and MCP editor control.
- SDL3 GPU rendering through Metal on macOS, Vulkan on Linux, and D3D12 on Windows, with an explicit software path.
- Project manager and editor shell with scene load/save, viewport navigation, undo, snap grid, property fields, and transform gizmos.
- Five editor modes: World, Layout, Architecture, Prop, and Life.
- Blockout tools for rough 3D spaces, including add/subtract brushes, ramps, doorways, stairs, face resize, per-face materials, and texture transforms.
- World-cell baking and streaming groundwork through `.fcell` files.
- MCP editor control for LLM-readable inspection, screenshots, camera control, typed editor commands, and repeatable scenario workflows.

Friendly Engine is still moving fast. See [PROGRESS.md](PROGRESS.md) for the current implementation status, including known failing checks.

## Quick Start

Requirements:

- Zig 0.16
- SDL3 and platform graphics dependencies
- A C toolchain

Build everything:

```sh
zig build
```

Run the editor:

```sh
zig build run-editor
```

Run the editor with the software viewport:

```sh
zig build run-editor -- --software
```

Run the client headlessly for a short smoke test:

```sh
zig build run-client -- --headless --frames 3
```

Inspect the engine surface:

```sh
zig build run-tools -- describe
```

Start the MCP editor-control server:

```sh
zig build run-mcp
```

## Current Status

Friendly Engine is pre-release. The foundation is in place, but not every validation command is currently green. The latest documented audit records:

- `zig build` passes.
- `zig build run-tools -- help` passes.
- `zig build run-tools -- describe` passes.
- `zig build test` currently has scene KDL and prop asset round-trip failures.
- `zig build check` currently fails on known oversized source modules that need splitting.

That status is intentional to show the real project state rather than a polished snapshot. The no-fallback rule applies: unsupported or broken paths should fail loudly.

## Documentation

- [Architecture](ARCHITECTURE.md): engine layers, module model, ECS, assets, and runtime targets.
- [Progress](PROGRESS.md): current implementation status and verification notes.
- [Roadmap](docs/ROADMAP.md): planned streams and work slices.
- [Codemap](docs/CODEMAP.md): source map for contributors and agents.
- [World Model](docs/WORLD.md): layered world compiler and streamable cell design.
- [Editor UI](docs/EDITOR_UI.md): editor layout and workflow model.
- [MCP Editor Control](docs/MCP.md): LLM-facing editor-control surface.
- [Extending](docs/EXTENDING.md): adding modules, components, requests, and runtime targets.

## Project Goals

- Support simple 3D games on macOS, Linux, and Windows first, then iOS and Android later.
- Make level blocking and texturing quick, spatial, and readable.
- Keep the editor editable by the engine framework itself.
- Keep the codebase and tools understandable for humans and LLM agents.
- Prefer small files, explicit data, and loud failures over hidden fallback behavior.

## License

No license file is currently included in this repository.
