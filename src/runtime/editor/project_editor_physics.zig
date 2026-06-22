const shared = @import("runtime_shared");
const project_editor_edit = @import("project_editor_edit.zig");
const project_editor_state = @import("project_editor_state.zig");

const scene_physics = shared.scene_physics;
const scene_physics_validate = shared.scene_physics_validate;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn setSelectedBody(state: *ProjectEditorState, body: ?scene_physics.Body) void {
    const idx = state.selected_object orelse {
        project_editor_state.setStatus(state, "No selection");
        return;
    };
    if (body) |value| {
        scene_physics_validate.validateBody(value) catch |err| {
            project_editor_state.setStatus(state, scene_physics_validate.errorMessage(err));
            return;
        };
    }
    project_editor_edit.pushUndoSnapshot(state);
    state.objects.items[idx].physics = body;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, if (body) |value| value.kind.label() else "Physics removed");
}

pub fn label(body: ?scene_physics.Body) []const u8 {
    return if (body) |value| value.kind.label() else "None";
}

pub fn withKind(existing: ?scene_physics.Body, kind: scene_physics.BodyKind) scene_physics.Body {
    var body = existing orelse scene_physics.Body{};
    body.kind = kind;
    return body;
}

pub fn cycleCollider(state: *ProjectEditorState) void {
    const idx = state.selected_object orelse return;
    var body = state.objects.items[idx].physics orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    body.collider = switch (body.collider) {
        .box => .sphere,
        .sphere => .capsule,
        .capsule => .mesh,
        .mesh => .box,
    };
    scene_physics_validate.validateBody(body) catch |err| {
        project_editor_state.setStatus(state, scene_physics_validate.errorMessage(err));
        return;
    };
    state.objects.items[idx].physics = body;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, body.collider.label());
}

pub fn adjustMass(state: *ProjectEditorState, delta: f32) void {
    const idx = state.selected_object orelse return;
    var body = state.objects.items[idx].physics orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    body.mass = @max(0.0, body.mass + delta);
    state.objects.items[idx].physics = body;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Mass changed");
}

pub fn adjustFriction(state: *ProjectEditorState, delta: f32) void {
    const idx = state.selected_object orelse return;
    var body = state.objects.items[idx].physics orelse return;
    project_editor_edit.pushUndoSnapshot(state);
    body.friction = @min(1.0, @max(0.0, body.friction + delta));
    state.objects.items[idx].physics = body;
    state.scene_dirty = true;
    project_editor_state.setStatus(state, "Friction changed");
}
