# MCP Scenarios

MCP scenarios are markdown briefs that an LLM can execute through
`friendly_engine_mcp`. They are the source of truth for authored content loops:
villages, buildings, terrain passes, prop dressing, lighting, and review shots.

They are deliberately not Zig generators. Zig should expose stable, strict MCP
tools. Scenario markdown should describe creative intent, concrete coordinates,
ordered tool calls, acceptance criteria, and follow-up gaps.

## Why

- Creative direction stays readable and editable by humans.
- LLMs can rerun, adapt, and critique the same scenario without recompiling.
- Engine work is driven by missing reusable MCP primitives, not one-off scripts.
- Scenario output can fail loudly when the MCP surface is missing a needed
  operation.

## File Location

Put runnable scenarios under `scenarios/`.

Recommended layout:

```text
scenarios/
  milburn/
    village-building.md
    lane-with-hedges.md
    cottage-cluster.md
  architecture/
    house-blockout.md
  props/
    stone-wall-kit.md
```

## Scenario Format

Each scenario should use this structure:

- **Scenario id**: stable kebab-case id.
- **Version**: increment when the expected result changes.
- **Intent**: the creative and workflow goal.
- **Starting state**: project, scene/mode, camera target, required assets.
- **Constraints**: no hand-written KDL/source edits, scale, style, performance
  limits, fail-loud requirements.
- **MCP preflight**: discovery and state checks before authoring.
- **MCP runbook**: ordered tool calls the LLM should make.
- **Design brief**: dimensions, materials, silhouettes, placement, variations.
- **Acceptance checks**: screenshots, object counts, selected object data,
  performance, and visual review prompts.
- **Missing MCP primitives**: explicit blockers the LLM must report rather than
  replacing with a Zig generator.
- **Run log**: append dated notes and screenshot paths.

## Execution Rules For LLMs

1. Read the full scenario before calling tools.
2. Use `tools/list`, `commands_list`, and `editor_describe` for preflight.
3. Execute through MCP tools only.
4. Do not create new procedural Zig scenario functions to satisfy content.
5. If an MCP primitive is missing, stop and report the missing tool in the run
   log. The next engine task should be to add that reusable primitive.
6. Use screenshots from `screenshot_viewport` or `screenshot_editor` as visual
   proof.
7. Save only through editor/MCP commands.

## MCP Primitive Guidelines

Good MCP primitives are small and reusable:

- `architecture_wall_point`
- `architecture_door_cut`
- `architecture_window_cut`
- `prop_new`
- `prop_source_sphere_add`
- `prop_modifier_bend_add`
- `terrain_sculpt`
- `camera_set`
- `screenshot_viewport`

Avoid MCP tools that encode a finished content concept:

- `architecture_make_specific_named_cottage`
- `world_generate_exact_final_village`
- `prop_create_oak_tree_17`

If a scenario needs a higher-level action, name it as a missing primitive in the
scenario, for example `architecture_roof_set`, `architecture_feature_add`, or
`object_transform_set`. Then implement the generic primitive once and let
markdown scenarios decide how to use it.
