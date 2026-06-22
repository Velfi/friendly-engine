---
name: run-doctor
description: Run the friendly-engine project doctor to diagnose broken FE project files. Use when the user asks to run doctor, diagnose or validate a Friendly Engine project, fix broken KDL files, inspect engine.kdl/world.kdl/scenes/layers/assets, or produce LLM-friendly repair output for an FE project.
---

# Run Project Doctor

Use this skill to diagnose authored Friendly Engine project data, not engine
source code. The doctor checks `engine.kdl`, world manifests, scene KDL files,
and referenced scene meshes/textures.

## Workflow

Copy this checklist and track progress:

```text
- [ ] Step 1: Identify the project path
- [ ] Step 2: Run doctor from the engine checkout
- [ ] Step 3: Read the first concrete failure
- [ ] Step 4: Fix the project file or asset reference
- [ ] Step 5: Re-run doctor
```

### Step 1: Identify The Project Path

Use the project path provided by the user. If they give a project name, locate
the project folder first. Common local projects live beside the engine checkout,
for example `/Users/zelda/Documents/botw-demo`.

Do not run the doctor from inside the project unless the command still executes
from the friendly-engine checkout. The build step lives in this repository.

### Step 2: Run Doctor

From `/Users/zelda/Documents/friendly-engine`:

```sh
zig build doctor -- --project /absolute/path/to/project
```

For the current repository as a sample project:

```sh
zig build doctor -- --project .
```

Use `--target <name>` when the project uses a non-default asset cache target.
Default target is `client-debug`.

Use `--bake` only when deeper world compiler validation is needed:

```sh
zig build doctor -- --project /absolute/path/to/project --bake
```

`--bake` may write baked cell output into the project cache, so mention that
when it matters.

### Step 3: Interpret Failures

Doctor output is already ordered for repair. Start with the first `fail:` line.
It usually names the broken file and the failing phase:

- `load engine config`: fix `engine.kdl`.
- `load world manifest`: fix `world.kdl` or another referenced world file.
- `world cell authoring scene is missing`: fix the manifest path or add the scene.
- `parse scene KDL`: fix the named scene file.
- `resolve scene meshes/textures`: rebuild/import assets or fix scene references.
- `bake world`: fix layer KDL or world compiler inputs.

Avoid adding fallbacks or silent defaults. Bad project data should fail loudly.

### Step 4: Fix And Re-run

After editing project files, re-run the same doctor command. Repeat until it
passes or the remaining failure is intentionally out of scope.

## Related Runtime Note

The editor uses `FRIENDLY_ENGINE_CLIENT_EXE` when Play Scene cannot locate
`friendly_engine_client`:

```sh
export FRIENDLY_ENGINE_CLIENT_EXE=/Users/zelda/Documents/friendly-engine/zig-out/bin/friendly_engine_client
```

Build the engine first with:

```sh
zig build
```
