# MCP Editor Control

`friendly_engine_mcp` is the agent-facing control surface for the editor. It is a stdio MCP server that forwards tool calls to the running editor control socket on `127.0.0.1:39743`.

## Starting It

The repo MCP config starts the server through Zig:

```sh
zig build run-mcp
```

For direct local testing after a build, this is equivalent:

```sh
./zig-out/bin/friendly_engine_mcp
```

The editor or project manager must already be running for calls that talk to the control socket. If it is not running, tool calls fail loudly with a connection error.

## Discovering Tools

Do not keep hand-written MCP tool lists in sync. The source of truth is:

```text
src/runtime/shared/editor_control_commands.zig
```

That registry defines each command name, MCP tool name, title, description, exposure tier, owner, argument policy, and JSON schema. The MCP server builds `tools/list` from the registry, and `commands_list` reports user-visible editor commands from the running app.

Useful discovery calls:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ./zig-out/bin/friendly_engine_mcp
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"commands_list","arguments":{}}}' | ./zig-out/bin/friendly_engine_mcp
printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"commands_scene_map","arguments":{}}}' | ./zig-out/bin/friendly_engine_mcp
```

## High-Value Tools

- `open_project`: open the selected project from Project Manager, or pass `object` for a named project.
- `editor_describe`: return project, mode, tool, viewport, camera, selection, counts, and status JSON.
- `objects_list`, `object_select`, `object_clear_selection`: inspect and manage scene selection.
- `commands_list`, `commands_scene_map`, `command_run`: inspect and execute user-visible editor commands.
- `camera_set`, `camera_preset`, `camera_random_angle`, `focus_in_viewport`, `zoom_to_focus`: set repeatable review views.
- `screenshot_editor`, `screenshot_viewport`: capture visual proof to `.friendly-engine/editor-control/screenshots/<project-name>/`.
- `perf_describe`: report frame timing, viewport backend, GPU backend, render command counts, and related diagnostics.
- `scene_new_architecture`, `architecture_*`, `terrain_*`, and `prop_*`: create and modify editor content through typed primitives and modifiers.
- `play_scene` and `turntable_capture`: exercise play mode and capture object review media.

Destructive tools are marked with the `destructive` tier in `tools/list`. Treat them as intentional operations, not convenience cleanup.

## Markdown Scenarios

Use markdown scenarios for authored content workflows. A scenario is an
LLM-readable runbook that calls reusable MCP primitives; it is not a procedural
Zig generator. See `docs/MCP_SCENARIOS.md` for the contract and
`scenarios/milburn/village-building.md` for the first Milburn building pass.

When a scenario needs an operation that MCP cannot express yet, add the missing
generic primitive to the scenario run log. Do not encode the finished building,
terrain pass, or prop set as a one-off Zig command.

## Calling Tools

Empty-argument tools must receive `{}` or omit `arguments`:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"editor_describe","arguments":{}}}' | ./zig-out/bin/friendly_engine_mcp
```

Field-based tools accept only the fields listed in their schema:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"camera_preset","arguments":{"object":"review"}}}' | ./zig-out/bin/friendly_engine_mcp
```

Strict JSON prop recipe tools preserve their object as JSON text before forwarding it to the editor:

```sh
printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"prop_source_sphere_add","arguments":{"source_id":"base","position":[0,0,0],"rotation":[0,0,0,1],"scale":[1,1,1],"radius":1,"segments":16,"rings":8}}}' | ./zig-out/bin/friendly_engine_mcp
```

## Adding Or Changing Tools

1. Add or update the registry entry in `src/runtime/shared/editor_control_commands.zig`.
2. Implement the editor command handling in `src/runtime/editor/editor_commands.zig` and related small modules.
3. Keep argument schemas strict. Unknown fields should fail instead of being ignored.
4. Run the registry tests with `zig build test`.
5. Verify from the running editor with `tools/list`, a real `tools/call`, and screenshot or `editor_describe` evidence when the command changes visible state.
