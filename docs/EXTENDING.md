# How to Extend

Step-by-step guides for adding engine surface area.

## Add a module (gem)

1. Create `src/modules/<name>/mod.zig` with `module_name`, `register`, `start`, `stop`.
2. Append one entry to `builtin_modules` in [src/modules/mod.zig](../src/modules/mod.zig) (`name`, `dependencies`, hooks, `enabled_by_default`, `config_flag`).
3. Add tests in the module file (lifecycle notification or API test).
4. Run `zig build test` and `zig build run-tools -- describe` to verify the catalog lists the new gem.

## Add a component

1. Define the component struct in the owning layer (usually `src/game/` or a gem).
2. Register it in [src/framework/components.zig](../src/framework/components.zig) with a string name and field schema.
3. Use `framework.World` component storage via the registry helpers.
4. Extend `describe` output if the component is part of the public engine surface.

## Add a request (command)

1. Implement a handler: `fn(ctx: ?*anyopaque, allocator: Allocator, payload: []const u8) ![]u8`.
2. Register on boot via `ServiceRegistry.registerRequest` in [src/modules/mod.zig](../src/modules/mod.zig) or [framework/introspection.zig](../src/framework/introspection.zig).
3. Wire `ServiceRegistry.applyToWorld` during bootstrap so handlers reach `world.requests`.
4. Document the request name and JSON payload shape in `describe` output.

## Add a runtime target

1. Add `src/runtime/<target>/main.zig` and call [src/runtime/bootstrap.zig](../src/runtime/bootstrap.zig) `bootWorld`.
2. Register the executable in [build.zig](../build.zig) with `friendly_engine` import.
3. Add a `RuntimeKind` variant in [src/root.zig](../src/root.zig) if needed.
4. Add verification command to [PROGRESS.md](../PROGRESS.md).
