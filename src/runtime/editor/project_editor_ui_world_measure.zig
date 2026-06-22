const std = @import("std");
const friendly_engine = @import("friendly_engine");
const shared = @import("runtime_shared");
const editor_math = shared.editor_math;
const shared_color = shared.color;
const project_editor_state = @import("project_editor_state.zig");
const project_editor_viewport = @import("project_editor_viewport.zig");

const core_ui = friendly_engine.modules.core_ui;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn buildControls(ui: *core_ui.UiContext, state: *ProjectEditorState) !void {
    var measure_buf: [96]u8 = undefined;
    const camera_dist = vec3Distance(state.camera.eye(), state.camera.target);
    const measure_text = if (state.world_measure_a != null and state.world_measure_b != null) blk: {
        const a = state.world_measure_a.?;
        const b = state.world_measure_b.?;
        break :blk std.fmt.bufPrint(&measure_buf, "Measure {d:.2}m  Camera {d:.2}m", .{ vec3Distance(a, b), camera_dist }) catch "Measure";
    } else blk: {
        break :blk std.fmt.bufPrint(&measure_buf, "Click two points  Camera {d:.2}m", .{camera_dist}) catch "Measure";
    };
    try core_ui.widgets_feedback.statusLabel(ui, measure_text);
}

pub fn handleClick(state: *ProjectEditorState, pt: editor_math.Vec3) void {
    if (state.world_measure_a == null) {
        state.world_measure_a = pt;
        state.world_measure_b = null;
        var buf: [64]u8 = undefined;
        project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Measure point A  Camera {d:.2}m", .{vec3Distance(state.camera.eye(), pt)}) catch "Measure point A");
        return;
    }
    state.world_measure_b = pt;
    const a = state.world_measure_a.?;
    var buf: [64]u8 = undefined;
    project_editor_state.setStatus(state, std.fmt.bufPrint(&buf, "Measure {d:.2}m", .{vec3Distance(a, pt)}) catch "Measure");
}

pub fn drawOverlay(state: *ProjectEditorState, vp_w: f32, vp_h: f32) void {
    const line_color: shared_color.Color = .{ .r = 255, .g = 180, .b = 80, .a = 230 };
    const point_color: shared_color.Color = .{ .r = 255, .g = 220, .b = 120, .a = 255 };
    if (state.world_measure_a) |a| {
        const sa = project_editor_state.projectViewportPoint(state, a, vp_w, vp_h) orelse return;
        project_editor_viewport.drawViewportSquare(state, sa.x, sa.y, 4, point_color);
        if (state.world_measure_b) |b| {
            const sb = project_editor_state.projectViewportPoint(state, b, vp_w, vp_h) orelse return;
            project_editor_viewport.drawViewportLine(state, sa.x, sa.y, sb.x, sb.y, line_color);
            project_editor_viewport.drawViewportSquare(state, sb.x, sb.y, 4, point_color);
        }
    }
    const eye = state.camera.eye();
    const target = state.camera.target;
    const s0 = project_editor_state.projectViewportPoint(state, eye, vp_w, vp_h) orelse return;
    const s1 = project_editor_state.projectViewportPoint(state, target, vp_w, vp_h) orelse return;
    const cam_color: shared_color.Color = .{ .r = 200, .g = 200, .b = 220, .a = 140 };
    project_editor_viewport.drawViewportLine(state, s0.x, s0.y, s1.x, s1.y, cam_color);
}

fn vec3Distance(a: editor_math.Vec3, b: editor_math.Vec3) f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dz = b.z - a.z;
    return @sqrt(dx * dx + dy * dy + dz * dz);
}
