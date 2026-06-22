const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;

const project_editor_state = @import("project_editor_state.zig");
const manifest = @import("project_editor_world_authoring_manifest.zig");

const ProjectEditorState = project_editor_state.ProjectEditorState;
const modules = friendly_engine.modules;

pub fn persistAddBlockout(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
) !void {
    const id = try manifest.cellForPoint(state, manifest.midpoint(min_pt, max_pt));
    const operation = try modules.local_csg.makeAddBlockOperation(id, .{
        .min = .{ min_pt.x, min_pt.y, min_pt.z },
        .max = .{ max_pt.x, max_pt.y, max_pt.z },
    });
    try modules.local_csg.appendLayerOperation(state.allocator, state.io, state.project_path, try manifest.pathForState(state), operation);
}

pub fn persistAddWedgeBlockout(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
) !void {
    const id = try manifest.cellForPoint(state, manifest.midpoint(min_pt, max_pt));
    const operation = try modules.local_csg.makeAddWedgeOperation(id, .{
        .min = .{ min_pt.x, min_pt.y, min_pt.z },
        .max = .{ max_pt.x, max_pt.y, max_pt.z },
    });
    try modules.local_csg.appendLayerOperation(state.allocator, state.io, state.project_path, try manifest.pathForState(state), operation);
}

pub fn persistDoorwaySubtract(
    state: *ProjectEditorState,
    opening_min: editor_math.Vec3,
    opening_max: editor_math.Vec3,
    wall_min: editor_math.Vec3,
    wall_max: editor_math.Vec3,
) !void {
    const id = try manifest.cellForPoint(state, manifest.midpoint(wall_min, wall_max));
    const operation = try modules.local_csg.makeDoorwaySubtractOperation(
        id,
        .{
            .min = .{ opening_min.x, opening_min.y, opening_min.z },
            .max = .{ opening_max.x, opening_max.y, opening_max.z },
        },
        .{
            .min = .{ wall_min.x, wall_min.y, wall_min.z },
            .max = .{ wall_max.x, wall_max.y, wall_max.z },
        },
    );
    try modules.local_csg.appendLayerOperation(state.allocator, state.io, state.project_path, try manifest.pathForState(state), operation);
}

pub fn persistSubtractBlockout(
    state: *ProjectEditorState,
    cut_min: editor_math.Vec3,
    cut_max: editor_math.Vec3,
    source_min: editor_math.Vec3,
    source_max: editor_math.Vec3,
) !void {
    const id = try manifest.cellForPoint(state, manifest.midpoint(source_min, source_max));
    const operation = try modules.local_csg.makeSubtractBlockOperation(
        id,
        .{
            .min = .{ cut_min.x, cut_min.y, cut_min.z },
            .max = .{ cut_max.x, cut_max.y, cut_max.z },
        },
        .{
            .min = .{ source_min.x, source_min.y, source_min.z },
            .max = .{ source_max.x, source_max.y, source_max.z },
        },
    );
    try modules.local_csg.appendLayerOperation(state.allocator, state.io, state.project_path, try manifest.pathForState(state), operation);
}

pub fn persistSubtractPrismBlockout(
    state: *ProjectEditorState,
    footprint: []const modules.local_csg.Point2,
    min_y: f32,
    max_y: f32,
    source_min: editor_math.Vec3,
    source_max: editor_math.Vec3,
) !void {
    const id = try manifest.cellForPoint(state, manifest.midpoint(source_min, source_max));
    var operation = try modules.local_csg.makeSubtractPrismOperation(
        state.allocator,
        id,
        footprint,
        min_y,
        max_y,
        .{
            .min = .{ source_min.x, source_min.y, source_min.z },
            .max = .{ source_max.x, source_max.y, source_max.z },
        },
    );
    defer operation.deinit(state.allocator);
    try modules.local_csg.appendLayerOperation(state.allocator, state.io, state.project_path, try manifest.pathForState(state), operation);
}

pub fn persistStairIntent(
    state: *ProjectEditorState,
    min_pt: editor_math.Vec3,
    max_pt: editor_math.Vec3,
) !void {
    const id = try manifest.cellForPoint(state, manifest.midpoint(min_pt, max_pt));
    try modules.local_csg.appendLayerOperation(state.allocator, state.io, state.project_path, try manifest.pathForState(state), try modules.local_csg.makeAddBlockOperation(id, .{
        .min = .{ min_pt.x, min_pt.y, min_pt.z },
        .max = .{ max_pt.x, max_pt.y, max_pt.z },
    }));
    try project_editor_state.markDirtyCell(state, "Local CSG", id, "stair blockout");
}
