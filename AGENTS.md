# Goals

- **Cross-platform 3D games**: The engine must support creating simple 3D games on all major platforms. Stage 1 targets Mac, Linux, and Windows. Stage 2 adds iOS and Android.
- **Fast level blocking and texturing**: The workflow should feel similar to [TrenchBroom](https://trenchbroom.github.io/) — blocking out levels and applying simple textures should be quick and easy.
- **The editor is editable by the editor**: The editor itself is written using the friendly-engine framework. Users should be able to create and extend the editor itself.
- **The editor is LLM friendly**: The editor is easy for LLMs to understand and make changes with.

## Development Principles

- **Small files, happy developers**: Eagerly break down large files into multiple smaller files while developing the project.
- **No Fallbacks**: things should fail fast and loudly. Don't add fallbacks, they're instant cruft.

## Visual Verification

- **Respect the configured engine path**: When launching Friendly Engine from another project, use the Friendly Engine path or command supplied by the ENV var instead of assuming a checkout location; the engine also ships `friendly_engine_mcp`, an MCP stdio server for agent control.
- **Use MCP editor control first**: When checking editor or project manager rendering, prefer the LLM-readable output from `friendly_engine_mcp` over OS-level capture tools. The MCP server is the agent-facing control surface for opening projects, describing editor state, listing commands and objects, moving the camera, capturing screenshots, generating scenes, editing terrain, and working with architecture and prop tools.
- **Discover tools instead of memorizing them**: `src/runtime/shared/editor_control_commands.zig` is the source of truth for MCP tool names, tiers, owners, and schemas. Use `tools/list` or the `commands_list` MCP tool when you need the current surface.
- **Use screenshots and diagnostics together**: With a running editor, call `screenshot_editor` for the full editor window or `screenshot_viewport` for the 3D viewport after a project is open. Read the returned JSON path under `.friendly-engine/editor-control/screenshots/<project-name>/`, then inspect that PNG with the LLM image viewer. Pair visual checks with `editor_describe` and `perf_describe` when debugging state, backend, frame timing, render command counts, or selection.
- **Avoid raw desktop capture as proof**: `screencapture`/OS screenshots can fail because of permissions or session state. Use them only as a fallback after the editor control tool is unavailable or unsuitable.

## Further Reading

- [Roadmap and parallel workstreams](docs/ROADMAP.md)
- [Implementation progress](PROGRESS.md)
- [MCP editor control guide](docs/MCP.md)
- [UI copy style](docs/UI_COPY.md)
- [How to extend the engine](docs/EXTENDING.md)
