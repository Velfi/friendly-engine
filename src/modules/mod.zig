const std = @import("std");
const framework = @import("../framework/mod.zig");
pub const ecs = @import("ecs/mod.zig");
pub const keyboard_mouse_controller = @import("keyboard_mouse_controller/mod.zig");
pub const controller_input = @import("controller_input/mod.zig");
pub const controller_rumble = @import("controller_rumble/mod.zig");
pub const physics3d = @import("physics3d/mod.zig");
pub const core_ui = @import("core_ui/mod.zig");
pub const luajit = @import("luajit/mod.zig");
pub const custom_gems = @import("custom_gems.zig");
pub const audio = @import("audio/mod.zig");
pub const persistence = @import("persistence/mod.zig");
pub const terrain = @import("terrain/mod.zig");
pub const splines = @import("splines/mod.zig");
pub const sectors = @import("sectors/mod.zig");
pub const buildings = @import("buildings/mod.zig");
pub const scatter = @import("scatter/mod.zig");
pub const grass = @import("grass/mod.zig");
pub const local_csg = @import("local_csg/mod.zig");
pub const atmosphere = @import("atmosphere/mod.zig");
pub const ocean = @import("ocean/mod.zig");
pub const water = @import("water/mod.zig");
pub const fps_player_controller = @import("fps_player_controller/mod.zig");
pub const editor_layout = @import("editor_layout/mod.zig");
pub const editor_world = @import("editor_world/mod.zig");
pub const editor_architecture = @import("editor_architecture/mod.zig");
pub const editor_prop = @import("editor_prop/mod.zig");
pub const editor_life = @import("editor_life/mod.zig");
pub const concept_paint = @import("concept_paint/mod.zig");

const registry_mod = @import("registry.zig");
const project_config_mod = @import("project_config.zig");

pub const RequestCatalogEntry = registry_mod.RequestCatalogEntry;
pub const ServiceRegistry = registry_mod.ServiceRegistry;
pub const ModuleHooks = registry_mod.ModuleHooks;
pub const ModuleGraph = registry_mod.ModuleGraph;
pub const ModuleScope = registry_mod.ModuleScope;
pub const OwnedProjectConfig = project_config_mod.OwnedProjectConfig;
pub const SceneEntry = project_config_mod.SceneEntry;

pub const BuiltinModuleConfigFlag = enum {
    physics,
    core_ui,
    audio,
    persistence,
};

pub const BuiltinModuleDesc = struct {
    hooks: ModuleHooks,
    enabled_by_default: bool = true,
    config_flag: ?BuiltinModuleConfigFlag = null,
};

pub const BuiltinModulesConfig = struct {
    enable_physics: bool = true,
    enable_core_ui: bool = true,
    enable_audio: bool = true,
    enable_persistence: bool = true,
};

fn registerEcs(registry: *ServiceRegistry) !void {
    try ecs.register(registry);
}

fn startEcs(world: *framework.World) !void {
    try ecs.start(world);
}

fn stopEcs(world: *framework.World) !void {
    try ecs.stop(world);
}

fn registerKeyboardMouseController(registry: *ServiceRegistry) !void {
    try keyboard_mouse_controller.register(registry);
}

fn startKeyboardMouseController(world: *framework.World) !void {
    try keyboard_mouse_controller.start(world);
}

fn stopKeyboardMouseController(world: *framework.World) !void {
    try keyboard_mouse_controller.stop(world);
}

fn registerControllerInput(registry: *ServiceRegistry) !void {
    try controller_input.register(registry);
}

fn startControllerInput(world: *framework.World) !void {
    try controller_input.start(world);
}

fn stopControllerInput(world: *framework.World) !void {
    try controller_input.stop(world);
}

fn registerControllerRumble(registry: *ServiceRegistry) !void {
    try controller_rumble.register(registry);
}

fn startControllerRumble(world: *framework.World) !void {
    try controller_rumble.start(world);
}

fn stopControllerRumble(world: *framework.World) !void {
    try controller_rumble.stop(world);
}

fn registerPhysics(registry: *ServiceRegistry) !void {
    try physics3d.register(registry);
}

fn startPhysics(world: *framework.World) !void {
    try physics3d.start(world);
}

fn stopPhysics(world: *framework.World) !void {
    try physics3d.stop(world);
}

fn registerCoreUi(registry: *ServiceRegistry) !void {
    try core_ui.register(registry);
}

fn startCoreUi(world: *framework.World) !void {
    try core_ui.start(world);
}

fn stopCoreUi(world: *framework.World) !void {
    try core_ui.stop(world);
}

fn registerLuaJit(registry: *ServiceRegistry) !void {
    try luajit.register(registry);
}

fn startLuaJit(world: *framework.World) !void {
    try luajit.start(world);
}

fn stopLuaJit(world: *framework.World) !void {
    try luajit.stop(world);
}

fn registerAudio(registry: *ServiceRegistry) !void {
    try audio.register(registry);
}

fn startAudio(world: *framework.World) !void {
    try audio.start(world);
}

fn stopAudio(world: *framework.World) !void {
    try audio.stop(world);
}

fn registerPersistence(registry: *ServiceRegistry) !void {
    try persistence.register(registry);
}

fn startPersistence(world: *framework.World) !void {
    try persistence.start(world);
}

fn stopPersistence(world: *framework.World) !void {
    try persistence.stop(world);
}

fn registerTerrain(registry: *ServiceRegistry) !void {
    try terrain.register(registry);
}

fn startTerrain(world: *framework.World) !void {
    try terrain.start(world);
}

fn stopTerrain(world: *framework.World) !void {
    try terrain.stop(world);
}

fn registerSplines(registry: *ServiceRegistry) !void {
    try splines.register(registry);
}

fn startSplines(world: *framework.World) !void {
    try splines.start(world);
}

fn stopSplines(world: *framework.World) !void {
    try splines.stop(world);
}

fn registerSectors(registry: *ServiceRegistry) !void {
    try sectors.register(registry);
}

fn startSectors(world: *framework.World) !void {
    try sectors.start(world);
}

fn stopSectors(world: *framework.World) !void {
    try sectors.stop(world);
}

fn registerBuildings(registry: *ServiceRegistry) !void {
    try buildings.register(registry);
}

fn startBuildings(world: *framework.World) !void {
    try buildings.start(world);
}

fn stopBuildings(world: *framework.World) !void {
    try buildings.stop(world);
}

fn registerScatter(registry: *ServiceRegistry) !void {
    try scatter.register(registry);
}

fn startScatter(world: *framework.World) !void {
    try scatter.start(world);
}

fn stopScatter(world: *framework.World) !void {
    try scatter.stop(world);
}

fn registerGrass(registry: *ServiceRegistry) !void {
    try grass.register(registry);
}

fn startGrass(world: *framework.World) !void {
    try grass.start(world);
}

fn stopGrass(world: *framework.World) !void {
    try grass.stop(world);
}

fn registerLocalCsg(registry: *ServiceRegistry) !void {
    try local_csg.register(registry);
}

fn startLocalCsg(world: *framework.World) !void {
    try local_csg.start(world);
}

fn stopLocalCsg(world: *framework.World) !void {
    try local_csg.stop(world);
}

fn registerAtmosphere(registry: *ServiceRegistry) !void {
    try atmosphere.register(registry);
}

fn startAtmosphere(world: *framework.World) !void {
    try atmosphere.start(world);
}

fn stopAtmosphere(world: *framework.World) !void {
    try atmosphere.stop(world);
}

fn registerWater(registry: *ServiceRegistry) !void {
    try water.register(registry);
}

fn startWater(world: *framework.World) !void {
    try water.start(world);
}

fn stopWater(world: *framework.World) !void {
    try water.stop(world);
}

fn registerFpsPlayerController(registry: *ServiceRegistry) !void {
    try fps_player_controller.register(registry);
}

fn startFpsPlayerController(world: *framework.World) !void {
    try fps_player_controller.start(world);
}

fn stopFpsPlayerController(world: *framework.World) !void {
    try fps_player_controller.stop(world);
}

fn registerEditorLayout(registry: *ServiceRegistry) !void {
    try editor_layout.register(registry);
}

fn startEditorLayout(world: *framework.World) !void {
    try editor_layout.start(world);
}

fn stopEditorLayout(world: *framework.World) !void {
    try editor_layout.stop(world);
}

fn registerEditorWorld(registry: *ServiceRegistry) !void {
    try editor_world.register(registry);
}

fn startEditorWorld(world: *framework.World) !void {
    try editor_world.start(world);
}

fn stopEditorWorld(world: *framework.World) !void {
    try editor_world.stop(world);
}

fn registerEditorArchitecture(registry: *ServiceRegistry) !void {
    try editor_architecture.register(registry);
}

fn startEditorArchitecture(world: *framework.World) !void {
    try editor_architecture.start(world);
}

fn stopEditorArchitecture(world: *framework.World) !void {
    try editor_architecture.stop(world);
}

fn registerEditorProp(registry: *ServiceRegistry) !void {
    try editor_prop.register(registry);
}

fn startEditorProp(world: *framework.World) !void {
    try editor_prop.start(world);
}

fn stopEditorProp(world: *framework.World) !void {
    try editor_prop.stop(world);
}

fn registerEditorLife(registry: *ServiceRegistry) !void {
    try editor_life.register(registry);
}

fn startEditorLife(world: *framework.World) !void {
    try editor_life.start(world);
}

fn stopEditorLife(world: *framework.World) !void {
    try editor_life.stop(world);
}

fn registerConceptPaint(registry: *ServiceRegistry) !void {
    try concept_paint.register(registry);
}

fn startConceptPaint(world: *framework.World) !void {
    try concept_paint.start(world);
}

fn stopConceptPaint(world: *framework.World) !void {
    try concept_paint.stop(world);
}

pub const builtin_modules = [_]BuiltinModuleDesc{
    .{
        .hooks = .{
            .name = ecs.module_name,
            .dependencies = &ecs.dependencies,
            .register = registerEcs,
            .start = startEcs,
            .stop = stopEcs,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = keyboard_mouse_controller.module_name,
            .dependencies = &keyboard_mouse_controller.dependencies,
            .register = registerKeyboardMouseController,
            .start = startKeyboardMouseController,
            .stop = stopKeyboardMouseController,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = controller_input.module_name,
            .dependencies = &controller_input.dependencies,
            .register = registerControllerInput,
            .start = startControllerInput,
            .stop = stopControllerInput,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = controller_rumble.module_name,
            .dependencies = &controller_rumble.dependencies,
            .register = registerControllerRumble,
            .start = startControllerRumble,
            .stop = stopControllerRumble,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = physics3d.module_name,
            .dependencies = &.{},
            .register = registerPhysics,
            .start = startPhysics,
            .stop = stopPhysics,
        },
        .enabled_by_default = false,
        .config_flag = .physics,
    },
    .{
        .hooks = .{
            .name = core_ui.module_name,
            .dependencies = &.{},
            .register = registerCoreUi,
            .start = startCoreUi,
            .stop = stopCoreUi,
        },
        .enabled_by_default = true,
        .config_flag = .core_ui,
    },
    .{
        .hooks = .{
            .name = luajit.module_name,
            .dependencies = &luajit.dependencies,
            .register = registerLuaJit,
            .start = startLuaJit,
            .stop = stopLuaJit,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = audio.module_name,
            .dependencies = &.{},
            .register = registerAudio,
            .start = startAudio,
            .stop = stopAudio,
        },
        .enabled_by_default = false,
        .config_flag = .audio,
    },
    .{
        .hooks = .{
            .name = persistence.module_name,
            .dependencies = &.{},
            .register = registerPersistence,
            .start = startPersistence,
            .stop = stopPersistence,
        },
        .enabled_by_default = true,
        .config_flag = .persistence,
    },
    .{
        .hooks = .{
            .name = terrain.module_name,
            .scope = .project,
            .dependencies = &.{},
            .register = registerTerrain,
            .start = startTerrain,
            .stop = stopTerrain,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = splines.module_name,
            .scope = .project,
            .dependencies = &.{terrain.module_name},
            .register = registerSplines,
            .start = startSplines,
            .stop = stopSplines,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = sectors.module_name,
            .scope = .project,
            .dependencies = &.{},
            .register = registerSectors,
            .start = startSectors,
            .stop = stopSectors,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = buildings.module_name,
            .scope = .project,
            .dependencies = &.{sectors.module_name},
            .register = registerBuildings,
            .start = startBuildings,
            .stop = stopBuildings,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = scatter.module_name,
            .scope = .project,
            .dependencies = &.{terrain.module_name},
            .register = registerScatter,
            .start = startScatter,
            .stop = stopScatter,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = grass.module_name,
            .scope = .project,
            .dependencies = &.{ terrain.module_name, scatter.module_name, physics3d.module_name },
            .register = registerGrass,
            .start = startGrass,
            .stop = stopGrass,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = local_csg.module_name,
            .scope = .project,
            .dependencies = &.{sectors.module_name},
            .register = registerLocalCsg,
            .start = startLocalCsg,
            .stop = stopLocalCsg,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = atmosphere.module_name,
            .scope = .project,
            .dependencies = &.{},
            .register = registerAtmosphere,
            .start = startAtmosphere,
            .stop = stopAtmosphere,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = water.module_name,
            .scope = .project,
            .dependencies = &.{},
            .register = registerWater,
            .start = startWater,
            .stop = stopWater,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = fps_player_controller.module_name,
            .scope = .project,
            .dependencies = &fps_player_controller.dependencies,
            .register = registerFpsPlayerController,
            .start = startFpsPlayerController,
            .stop = stopFpsPlayerController,
        },
        .enabled_by_default = false,
    },
    .{
        .hooks = .{
            .name = editor_layout.module_name,
            .scope = .editor,
            .dependencies = &editor_layout.dependencies,
            .register = registerEditorLayout,
            .start = startEditorLayout,
            .stop = stopEditorLayout,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = editor_world.module_name,
            .scope = .editor,
            .dependencies = &editor_world.dependencies,
            .register = registerEditorWorld,
            .start = startEditorWorld,
            .stop = stopEditorWorld,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = editor_architecture.module_name,
            .scope = .editor,
            .dependencies = &editor_architecture.dependencies,
            .register = registerEditorArchitecture,
            .start = startEditorArchitecture,
            .stop = stopEditorArchitecture,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = editor_prop.module_name,
            .scope = .editor,
            .dependencies = &editor_prop.dependencies,
            .register = registerEditorProp,
            .start = startEditorProp,
            .stop = stopEditorProp,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = editor_life.module_name,
            .scope = .editor,
            .dependencies = &editor_life.dependencies,
            .register = registerEditorLife,
            .start = startEditorLife,
            .stop = stopEditorLife,
        },
        .enabled_by_default = true,
    },
    .{
        .hooks = .{
            .name = concept_paint.module_name,
            .scope = .editor,
            .dependencies = &concept_paint.dependencies,
            .register = registerConceptPaint,
            .start = startConceptPaint,
            .stop = stopConceptPaint,
        },
        .enabled_by_default = true,
    },
};

pub fn isModuleEnabled(desc: BuiltinModuleDesc, config: BuiltinModulesConfig) bool {
    const flag = desc.config_flag orelse return true;
    return switch (flag) {
        .physics => config.enable_physics,
        .core_ui => config.enable_core_ui,
        .audio => config.enable_audio,
        .persistence => config.enable_persistence,
    };
}

pub fn addBuiltinModules(graph: *ModuleGraph) !void {
    try addBuiltinModulesWithConfig(graph, .{});
}

pub fn addBuiltinModulesWithConfig(graph: *ModuleGraph, config: BuiltinModulesConfig) !void {
    for (builtin_modules) |desc| {
        if (isModuleEnabled(desc, config)) {
            try graph.add(desc.hooks);
        }
    }
}

pub fn initBuiltinGraph(allocator: std.mem.Allocator) !ModuleGraph {
    return initBuiltinGraphWithConfig(allocator, .{});
}

pub fn initBuiltinGraphWithConfig(allocator: std.mem.Allocator, config: BuiltinModulesConfig) !ModuleGraph {
    var graph = ModuleGraph.init(allocator);
    errdefer graph.deinit();
    try addBuiltinModulesWithConfig(&graph, config);
    return graph;
}

pub fn defaultProjectConfig(allocator: std.mem.Allocator) !OwnedProjectConfig {
    var names = std.ArrayList([]const u8).empty;
    defer names.deinit(allocator);
    for (builtin_modules) |desc| {
        if (desc.enabled_by_default) try names.append(allocator, desc.hooks.name);
    }
    return project_config_mod.defaultProjectConfig(allocator, names.items);
}

pub const parseProjectConfigBytes = project_config_mod.parseProjectConfigBytes;
pub const defaultProjectConfigWithModules = project_config_mod.defaultProjectConfig;
pub const formatProjectConfig = project_config_mod.formatProjectConfig;
pub const loadProjectConfig = project_config_mod.loadProjectConfig;
pub const loadProjectConfigInProject = project_config_mod.loadProjectConfigInProject;
pub const addProjectCustomGems = custom_gems.addProjectCustomGems;
pub const swapProjectCustomGems = custom_gems.swapProjectCustomGems;

pub fn moduleCatalogEntries() []const BuiltinModuleDesc {
    return &builtin_modules;
}

test {
    _ = @import("mod_tests.zig");
}
