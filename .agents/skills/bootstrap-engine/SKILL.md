---
name: bootstrap-engine
description: Install or locate the required Zig toolchain, refresh every Friendly Engine vendored dependency, build generated assets, verify the checkout, and launch the editor. Use when a developer wants a from-scratch setup path that gets Friendly Engine running.
---

# Bootstrap Engine

Use this skill when a checkout needs to go from "I just cloned it" to a running
Friendly Engine editor. This is the full setup path: Zig, vendored dependencies,
generated assets, build verification, and editor launch.

## Workflow

1. Start from the repository root.
2. Install or locate Zig `0.16.x`.
3. Put the selected Zig first on `PATH` for the current shell session.
4. Run every vendoring script with `--replace`.
5. Fetch Zig package dependencies into the local Zig cache.
6. Run the normal project bootstrap commands.
7. Launch the editor with the software backend first.
8. Stop at the first real failure and report the concrete command and error.

## Zig Toolchain

First check for an acceptable Zig:

```sh
command -v zig
zig version
```

If Zig is missing or not `0.16.x`, install a repo-local toolchain:

```sh
sh .agents/skills/bootstrap-engine/scripts/install_zig.sh
export PATH="$PWD/.agent-tools/zig/0.16.0/bin:$PATH"
zig version
```

The installer uses Zig's official download index, verifies the published shasum,
and writes only under `.agent-tools/`. It supports macOS and Linux on `x86_64`
and `aarch64`. On Windows, install Zig `0.16.x` from the official Zig download
index, then rerun this skill from a shell where `zig version` prints `0.16.x`.

Network access is required when the repo-local toolchain is not already present.
Ask for escalation before running the installer if the sandbox blocks network
access.

## Vendor Everything

Run these from the repository root, in this order:

```sh
zig run .agents/skills/vendor-sdl3/scripts/vendor_sdl3.zig -- --replace
zig run .agents/skills/vendor-zphysics/scripts/vendor_zphysics.zig -- --replace
zig run .agents/skills/vendor-audio/scripts/vendor_audio.zig -- --replace
zig run .agents/skills/vendor-fonts/scripts/vendor_fonts.zig -- --replace
zig run .agents/skills/vendor-luajit/scripts/vendor_luajit.zig -- --replace
zig run .agents/skills/vendor-pluto/scripts/vendor_pluto.zig -- --replace
zig run .agents/skills/vendor-xatlas/scripts/vendor_xatlas.zig -- --replace
```

If a vendoring command needs network access, request escalation and rerun that
same command. Do not skip a vendor. Do not replace `--replace` with a softer
mode.

## Fetch Zig Packages

`build.zig.zon` still includes remote Zig package dependencies such as
`zigimg`. Populate Zig's package cache explicitly:

```sh
zig build --fetch
```

If this needs network access, request escalation and rerun the same command.
Do not edit `build.zig.zon` just to avoid the fetch.

## Bootstrap And Verify

After vendoring, generate outputs and run the verification sequence. The
minimum command set is:

```sh
zig build --fetch
zig build
zig build run-tools -- write-schemas
zig build bake
zig build run-tools -- describe
zig build test
zig build check
zig build run-client -- --headless --frames 3
zig build run-editor -- --software --frames 5
```

The project may document known `zig build test` or `zig build check` failures.
Run the commands anyway, capture the first concrete failure, and report it
instead of calling the checkout fully bootstrapped.

## Get The Editor Running

Start with the software backend because it is the most predictable setup path:

```sh
zig build run-editor -- --software
```

For GPU validation after the software editor works:

```sh
zig build run-editor
```

For LLM editor control after the build succeeds:

```sh
zig build run-mcp
```

Prefer the MCP editor-control tools for visual verification once the editor is
running. Use `commands_list`, `editor_describe`, `perf_describe`, and
`screenshot_viewport` rather than raw desktop screenshots.

## Guardrails

- Do not install a global Zig unless the user explicitly asks for it.
- Do not use a Zig version outside `0.16.x`.
- Do not silently skip vendor refreshes, schema generation, asset baking, or
  smoke checks.
- Treat `.agent-tools/`, `.zig-cache/`, `zig-cache/`, `zig-out/`,
  `assets/cache/`, and `assets/bundles/` as generated outputs.
- Leave authored project data alone unless the user explicitly asks to edit it.
