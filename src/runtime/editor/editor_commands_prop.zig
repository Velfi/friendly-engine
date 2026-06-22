const std = @import("std");
const shared = @import("runtime_shared");
const editor_command_file = @import("editor_command_file.zig");
const project_editor_prop = @import("project_editor_prop.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_types = @import("project_editor_types.zig");

const CommandFile = editor_command_file.CommandFile;
const ProjectEditorState = project_editor_state.ProjectEditorState;

pub fn handles(command_name: []const u8) bool {
    return std.mem.startsWith(u8, command_name, "prop.");
}

pub fn execute(allocator: std.mem.Allocator, command: CommandFile, editor_state: *ProjectEditorState) ![]u8 {
    if (std.mem.eql(u8, command.name, "prop.open")) {
        const asset_id = command.object orelse return error.MissingObject;
        editor_state.mode = .prop_creation;
        project_editor_prop.openAssetForEditing(editor_state, asset_id) catch |err| {
            project_editor_prop.setOpenAssetErrorDetail(editor_state, asset_id, err, @errorReturnTrace()) catch {};
            return err;
        };
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"asset\":\"{s}\",\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            asset_id,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.instance-place")) {
        const asset_id = command.asset orelse return error.MissingObject;
        const x = command.point_x orelse return error.MissingPoint;
        const z = command.point_z orelse return error.MissingPoint;
        const point: shared.editor_math.Vec3 = .{ .x = x, .y = command.point_y orelse 0, .z = z };
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .asset;
        const before_count = editor_state.objects.items.len;
        try project_editor_prop.instantiatePropAssetAt(editor_state, asset_id, point);
        if (editor_state.objects.items.len == before_count) return error.UnknownPropAsset;
        const idx = editor_state.objects.items.len - 1;
        if (command.yaw) |yaw| editor_state.objects.items[idx].rotation.y = yaw;
        if (command.scale_world) |scale| editor_state.objects.items[idx].scale = .{ .x = scale, .y = scale, .z = scale };
        editor_state.scene_dirty = true;
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"asset\":\"{s}\",\"object\":\"{s}\",\"object_id\":{d},\"position\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"rotation\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"scale\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            asset_id,
            editor_state.objects.items[idx].name,
            editor_state.objects.items[idx].id,
            editor_state.objects.items[idx].position.x,
            editor_state.objects.items[idx].position.y,
            editor_state.objects.items[idx].position.z,
            editor_state.objects.items[idx].rotation.x,
            editor_state.objects.items[idx].rotation.y,
            editor_state.objects.items[idx].rotation.z,
            editor_state.objects.items[idx].scale.x,
            editor_state.objects.items[idx].scale.y,
            editor_state.objects.items[idx].scale.z,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.new")) {
        const asset_id = command.object orelse return error.MissingObject;
        try project_editor_prop_asset.createCustomAssetWorkingCopy(editor_state, asset_id, asset_id, "");
        return assetStatusJson(allocator, command, asset_id, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.modify")) {
        const asset_id = command.object orelse return error.MissingObject;
        project_editor_prop_asset.modifyAssetWorkingCopy(editor_state, asset_id) catch |err| {
            project_editor_prop.setOpenAssetErrorDetail(editor_state, asset_id, err, @errorReturnTrace()) catch {};
            return err;
        };
        return assetStatusJson(allocator, command, asset_id, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-point")) {
        const x = command.point_x orelse return error.MissingPoint;
        const z = command.point_z orelse return error.MissingPoint;
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        editor_state.prop_sketch_mode = .face;
        const point: shared.editor_math.Vec3 = .{ .x = x, .y = command.point_y orelse 0, .z = z };
        editor_state.active_gesture.begin(.draw_face);
        editor_state.prop_sketch_points.append(editor_state.allocator, point) catch |err| {
            editor_state.active_gesture.cancel();
            return err;
        };
        editor_state.active_gesture.commit();
        var status_buf: [80]u8 = undefined;
        project_editor_state.setStatus(editor_state, std.fmt.bufPrint(&status_buf, "Sketch point {d} placed", .{editor_state.prop_sketch_points.items.len}) catch "Sketch point placed");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            point.x,
            point.y,
            point.z,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-profile-point")) {
        const x = command.point_x orelse return error.MissingPoint;
        const z = command.point_z orelse return error.MissingPoint;
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        editor_state.prop_sketch_mode = .curve;
        const point: shared.editor_math.Vec3 = .{ .x = x, .y = command.point_y orelse 0, .z = z };
        editor_state.active_gesture.begin(.draw_profile);
        editor_state.prop_sketch_points.append(editor_state.allocator, point) catch |err| {
            editor_state.active_gesture.cancel();
            return err;
        };
        editor_state.active_gesture.commit();
        var status_buf: [80]u8 = undefined;
        project_editor_state.setStatus(editor_state, std.fmt.bufPrint(&status_buf, "Profile point {d} placed", .{editor_state.prop_sketch_points.items.len}) catch "Profile point placed");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            point.x,
            point.y,
            point.z,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-path-point")) {
        const x = command.point_x orelse return error.MissingPoint;
        const z = command.point_z orelse return error.MissingPoint;
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        editor_state.prop_sketch_mode = .path;
        const point: shared.editor_math.Vec3 = .{ .x = x, .y = command.point_y orelse 0, .z = z };
        editor_state.active_gesture.begin(.draw_path);
        editor_state.prop_sketch_points.append(editor_state.allocator, point) catch |err| {
            editor_state.active_gesture.cancel();
            return err;
        };
        editor_state.active_gesture.commit();
        var status_buf: [80]u8 = undefined;
        project_editor_state.setStatus(editor_state, std.fmt.bufPrint(&status_buf, "Path point {d} placed", .{editor_state.prop_sketch_points.items.len}) catch "Path point placed");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            point.x,
            point.y,
            point.z,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-point-update")) {
        const point_index = command.vertex orelse return error.MissingPoint;
        if (point_index >= editor_state.prop_sketch_points.items.len) return error.InvalidShapePoint;
        var point = editor_state.prop_sketch_points.items[point_index];
        point.x = command.point_x orelse point.x;
        point.y = command.point_y orelse point.y;
        point.z = command.point_z orelse point.z;
        if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y) or !std.math.isFinite(point.z)) return error.InvalidShapePoint;
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        editor_state.prop_sketch_points.items[point_index] = point;
        project_editor_state.setStatus(editor_state, "Sketch point updated");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"vertex\":{d},\"point\":{{\"x\":{d:.6},\"y\":{d:.6},\"z\":{d:.6}}},\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            point_index,
            point.x,
            point.y,
            point.z,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-clear")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        editor_state.prop_sketch_points.clearRetainingCapacity();
        project_editor_state.setStatus(editor_state, "Sketch cleared");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":0,\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-operation")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        if (command.amount) |amount| {
            if (!std.math.isFinite(amount) or amount <= 0) return error.InvalidShapeOperationAmount;
            editor_state.prop_sketch_amount = amount;
        }
        if (command.segments) |segments| {
            if (segments < 3 or segments > 128) return error.InvalidRevolveSegments;
            editor_state.prop_sketch_segments = segments;
        }
        project_editor_state.setStatus(editor_state, "Shape operation updated");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"amount\":{d:.6},\"segments\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_amount,
            editor_state.prop_sketch_segments,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-solidify")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.solidifySelected(editor_state, editor_state.prop_sketch_amount);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-extrude")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.extrudePathSelected(editor_state, editor_state.prop_sketch_amount);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-inset")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.insetSelected(editor_state, editor_state.prop_sketch_amount);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-bevel")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.bevelSelected(editor_state, editor_state.prop_sketch_amount);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-cut")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.cutSelected(editor_state, editor_state.prop_sketch_amount);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.sketch-revolve")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.revolveSelected(editor_state);
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"points\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            editor_state.prop_sketch_points.items.len,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.render-mode")) {
        const mode_name = command.object orelse return error.MissingObject;
        const mode = try parseRenderMode(mode_name);
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.shading_mode = mode;
        project_editor_state.setStatus(editor_state, mode.label());
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"mode\":\"{s}\",\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            mode.label(),
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.texture-quality")) {
        const quality_name = command.object orelse return error.MissingObject;
        const quality = try parseTextureQuality(quality_name);
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .material;
        editor_state.prop_texture_quality = quality;
        var status_buf: [48]u8 = undefined;
        project_editor_state.setStatus(editor_state, std.fmt.bufPrint(&status_buf, "Texture detail {d}x", .{quality}) catch "Texture detail");
        return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"quality\":{d},\"status\":\"{s}\"}}\n", .{
            command.id,
            command.name,
            quality,
            editor_state.status_buf[0..editor_state.status_len],
        });
    }
    if (std.mem.eql(u8, command.name, "prop.mesh-clear")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop_asset.clearSelectedMesh(editor_state);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.primitive-seed-add")) {
        const kind = parsePrimitiveKind(command.primitive orelse return error.InvalidArguments) orelse return error.InvalidArguments;
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop_asset.appendPrimitiveSeedSelected(editor_state, kind, .{
            .width = command.width orelse 1.0,
            .height = command.height orelse 1.0,
            .depth = command.depth orelse 1.0,
            .radius = command.radius orelse 0.5,
            .segments = command.segments orelse 16,
        });
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.mesh-mirror")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.mirrorSelectedX(editor_state);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.mesh-array")) {
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop.arraySelectedX(editor_state);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.mesh-ellipsoid")) {
        const payload = command.object orelse return error.MissingObject;
        const values = try parseFloatTuple(payload, 8);
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop_asset.appendEllipsoidSelected(editor_state, .{
            .center = .{ .x = values[0], .y = values[1], .z = values[2] },
            .radius = .{ .x = values[3], .y = values[4], .z = values[5] },
            .segments = @intFromFloat(@max(4, values[6])),
            .rings = @intFromFloat(@max(4, values[7])),
        });
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.mesh-cone")) {
        const payload = command.object orelse return error.MissingObject;
        const values = try parseFloatTuple(payload, 9);
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop_asset.appendConeSelected(editor_state, .{
            .center = .{ .x = values[0], .y = values[1], .z = values[2] },
            .direction = .{ .x = values[3], .y = values[4], .z = values[5] },
            .radius = values[6],
            .height = values[7],
            .segments = @intFromFloat(@max(3, values[8])),
        });
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.mesh-oval-slab")) {
        const payload = command.object orelse return error.MissingObject;
        const values = try parseFloatTuple(payload, 11);
        editor_state.mode = .prop_creation;
        editor_state.prop_workspace_mode = .edit;
        editor_state.prop_tool = .edit;
        try project_editor_prop_asset.appendOvalSlabSelected(editor_state, .{
            .position = .{ .x = values[0], .y = values[1], .z = values[2] },
            .rotation = .{ .x = values[3], .y = values[4], .z = values[5], .w = values[6] },
            .radius_x = values[7],
            .radius_y = values[8],
            .depth = values[9],
            .segments = @intFromFloat(@max(5, values[10])),
        });
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.source-sphere-add")) {
        const parsed = try parseCommandObject(project_editor_prop_asset.SourceSphereSpec, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.addSourceSphereSelected(editor_state, parsed.value);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.source-transform-update")) {
        const parsed = try parseCommandObject(project_editor_prop_asset.SourceTransformUpdate, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.updateSourceTransformSelected(editor_state, parsed.value);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.source-delete")) {
        const parsed = try parseCommandObject(struct { source_id: []const u8 }, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.deleteSourceSelected(editor_state, parsed.value.source_id);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.modifier-bend-add")) {
        const parsed = try parseCommandObject(project_editor_prop_asset.BendModifierSpec, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.addBendModifierSelected(editor_state, parsed.value);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.modifier-taper-add")) {
        const parsed = try parseCommandObject(project_editor_prop_asset.TaperModifierSpec, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.addTaperModifierSelected(editor_state, parsed.value);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.modifier-lattice-add")) {
        const parsed = try parseCommandObject(project_editor_prop_asset.LatticeModifierSpec, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.addLatticeModifierSelected(editor_state, parsed.value);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.modifier-update")) {
        try updateModifier(allocator, command, editor_state);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.modifier-delete")) {
        const parsed = try parseCommandObject(struct { modifier_id: []const u8 }, allocator, command);
        defer parsed.deinit();
        prepEdit(editor_state);
        try project_editor_prop_asset.deleteModifierSelected(editor_state, parsed.value.modifier_id);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.recipe-rebake")) {
        prepEdit(editor_state);
        try project_editor_prop_asset.rebakeSelectedRecipe(editor_state);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.material-object")) {
        const material_path = command.material_path orelse return error.MissingObject;
        prepMaterial(editor_state);
        try project_editor_prop_asset.setObjectMaterialSelected(editor_state, materialSpec(command, material_path));
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.material-face")) {
        const material_path = command.material_path orelse return error.MissingObject;
        prepMaterial(editor_state);
        const spec = faceMaterialSpec(command, material_path, command.face_index orelse return error.InvalidArguments);
        try project_editor_prop_asset.setFaceMaterialSelected(editor_state, spec);
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.texture-fill")) {
        prepMaterial(editor_state);
        try project_editor_prop_asset.fillTextureSelected(editor_state, .{
            .r = command.r orelse return error.InvalidArguments,
            .g = command.g orelse return error.InvalidArguments,
            .b = command.b orelse return error.InvalidArguments,
            .a = command.a orelse 255,
        });
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.texture-unwrap")) {
        prepMaterial(editor_state);
        const report = try project_editor_prop_asset.unwrapTextureSelected(editor_state);
        return std.fmt.allocPrint(
            allocator,
            "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"charts\":{d},\"atlas_width\":{d},\"atlas_height\":{d},\"duplicated_vertices\":{d},\"status\":\"{s}\"}}\n",
            .{
                command.id,
                command.name,
                report.chart_count,
                report.atlas_width,
                report.atlas_height,
                report.duplicated_vertex_count,
                editor_state.status_buf[0..editor_state.status_len],
            },
        );
    }
    if (std.mem.eql(u8, command.name, "prop.texture-paint-uv")) {
        prepMaterial(editor_state);
        try project_editor_prop_asset.paintTextureSelectedAtUv(editor_state, .{
            .u = command.u orelse return error.InvalidArguments,
            .v = command.v orelse return error.InvalidArguments,
            .r = command.r orelse return error.InvalidArguments,
            .g = command.g orelse return error.InvalidArguments,
            .b = command.b orelse return error.InvalidArguments,
            .a = command.a orelse 255,
            .radius = command.radius orelse 0.05,
            .opacity = command.opacity orelse 1.0,
            .hardness = command.hardness orelse 0.72,
        });
        return statusJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.metadata")) {
        return metadataJson(allocator, command, editor_state);
    }
    if (std.mem.eql(u8, command.name, "prop.delete") or std.mem.eql(u8, command.name, "prop.restore")) {
        return deleteRestoreJson(allocator, command, editor_state);
    }
    return error.UnknownEditorCommand;
}

fn prepEdit(editor_state: *ProjectEditorState) void {
    editor_state.mode = .prop_creation;
    editor_state.prop_workspace_mode = .edit;
    editor_state.prop_tool = .edit;
}

fn prepMaterial(editor_state: *ProjectEditorState) void {
    editor_state.mode = .prop_creation;
    editor_state.prop_workspace_mode = .edit;
    editor_state.prop_tool = .material;
}

fn materialSpec(command: CommandFile, material_path: []const u8) project_editor_prop_asset.MaterialSpec {
    return .{
        .material_path = material_path,
        .r = command.r orelse 255,
        .g = command.g orelse 255,
        .b = command.b orelse 255,
        .a = command.a orelse 255,
        .scale_world = command.scale_world orelse 1.0,
        .rotation_deg = command.rotation_deg orelse 0.0,
        .offset_u = command.offset_u orelse 0.0,
        .offset_v = command.offset_v orelse 0.0,
    };
}

fn faceMaterialSpec(command: CommandFile, material_path: []const u8, face_index: usize) project_editor_prop_asset.FaceMaterialSpec {
    return .{
        .face_index = face_index,
        .material_path = material_path,
        .r = command.r orelse 255,
        .g = command.g orelse 255,
        .b = command.b orelse 255,
        .a = command.a orelse 255,
        .scale_world = command.scale_world orelse 1.0,
        .rotation_deg = command.rotation_deg orelse 0.0,
        .offset_u = command.offset_u orelse 0.0,
        .offset_v = command.offset_v orelse 0.0,
    };
}

fn updateModifier(allocator: std.mem.Allocator, command: CommandFile, editor_state: *ProjectEditorState) !void {
    const payload = command.object orelse return error.MissingObject;
    const kind_probe = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer kind_probe.deinit();
    const object = switch (kind_probe.value) {
        .object => |value| value,
        else => return error.InvalidArguments,
    };
    const kind_value = object.get("kind") orelse return error.InvalidArguments;
    const kind = switch (kind_value) {
        .string => |value| value,
        else => return error.InvalidArguments,
    };
    prepEdit(editor_state);
    if (std.mem.eql(u8, kind, "bend")) {
        const BendUpdate = struct { modifier_id: []const u8, source_id: []const u8, kind: []const u8, axis: []const u8, amount: f32 };
        const parsed = try parseStrictJson(BendUpdate, allocator, payload);
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.kind, "bend")) return error.InvalidArguments;
        try project_editor_prop_asset.updateBendModifierSelected(editor_state, .{
            .modifier_id = parsed.value.modifier_id,
            .source_id = parsed.value.source_id,
            .axis = parsed.value.axis,
            .amount = parsed.value.amount,
        });
        return;
    }
    if (std.mem.eql(u8, kind, "taper")) {
        const TaperUpdate = struct { modifier_id: []const u8, source_id: []const u8, kind: []const u8, axis: []const u8, amount: f32 };
        const parsed = try parseStrictJson(TaperUpdate, allocator, payload);
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.kind, "taper")) return error.InvalidArguments;
        try project_editor_prop_asset.updateTaperModifierSelected(editor_state, .{
            .modifier_id = parsed.value.modifier_id,
            .source_id = parsed.value.source_id,
            .axis = parsed.value.axis,
            .amount = parsed.value.amount,
        });
        return;
    }
    if (std.mem.eql(u8, kind, "lattice")) {
        const LatticeUpdate = struct { modifier_id: []const u8, source_id: []const u8, kind: []const u8, dimensions: [3]u32, points: []const project_editor_prop_asset.LatticePointSpec };
        const parsed = try parseStrictJson(LatticeUpdate, allocator, payload);
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.kind, "lattice")) return error.InvalidArguments;
        try project_editor_prop_asset.updateLatticeModifierSelected(editor_state, .{
            .modifier_id = parsed.value.modifier_id,
            .source_id = parsed.value.source_id,
            .dimensions = parsed.value.dimensions,
            .points = parsed.value.points,
        });
        return;
    }
    return error.InvalidArguments;
}

fn metadataJson(allocator: std.mem.Allocator, command: CommandFile, editor_state: *ProjectEditorState) ![]u8 {
    const payload = command.object orelse return error.MissingObject;
    const split = std.mem.indexOfScalar(u8, payload, '|') orelse return error.InvalidArguments;
    const label = payload[0..split];
    const tags = payload[split + 1 ..];
    const asset_id = project_editor_prop_asset.selectedAssetId(editor_state) orelse return error.MissingObject;
    try project_editor_prop_asset.updateAssetMetadata(editor_state, asset_id, label, tags);
    editor_state.mode = .prop_creation;
    editor_state.prop_workspace_mode = .edit;
    editor_state.prop_tool = .asset;
    var out = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"asset\":", .{});
    try appendJsonString(allocator, &out, asset_id);
    try appendFmt(allocator, &out, ",\"label\":", .{});
    try appendJsonString(allocator, &out, label);
    try appendFmt(allocator, &out, ",\"tags\":", .{});
    try appendJsonString(allocator, &out, tags);
    try appendFmt(allocator, &out, ",\"status\":", .{});
    try appendJsonString(allocator, &out, editor_state.status_buf[0..editor_state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn deleteRestoreJson(allocator: std.mem.Allocator, command: CommandFile, editor_state: *ProjectEditorState) ![]u8 {
    const asset_id = command.object orelse (project_editor_prop_asset.selectedAssetId(editor_state) orelse return error.MissingObject);
    const deleted = std.mem.eql(u8, command.name, "prop.delete");
    try project_editor_prop_asset.setAssetDeleted(editor_state, asset_id, deleted);
    editor_state.mode = .prop_creation;
    editor_state.prop_workspace_mode = .edit;
    editor_state.prop_tool = .asset;
    var out = try std.ArrayList(u8).initCapacity(allocator, 192);
    defer out.deinit(allocator);
    try appendFmt(allocator, &out, "{{\"ok\":true,\"id\":", .{});
    try appendJsonString(allocator, &out, command.id);
    try appendFmt(allocator, &out, ",\"command\":", .{});
    try appendJsonString(allocator, &out, command.name);
    try appendFmt(allocator, &out, ",\"asset\":", .{});
    try appendJsonString(allocator, &out, asset_id);
    try appendFmt(allocator, &out, ",\"deleted\":{},\"status\":", .{deleted});
    try appendJsonString(allocator, &out, editor_state.status_buf[0..editor_state.status_len]);
    try appendFmt(allocator, &out, "}}\n", .{});
    return out.toOwnedSlice(allocator);
}

fn assetStatusJson(allocator: std.mem.Allocator, command: CommandFile, asset_id: []const u8, editor_state: *const ProjectEditorState) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"asset\":\"{s}\",\"status\":\"{s}\"}}\n", .{
        command.id,
        command.name,
        asset_id,
        editor_state.status_buf[0..editor_state.status_len],
    });
}

fn statusJson(allocator: std.mem.Allocator, command: CommandFile, editor_state: *const ProjectEditorState) ![]u8 {
    return std.fmt.allocPrint(allocator, "{{\"ok\":true,\"id\":\"{s}\",\"command\":\"{s}\",\"status\":\"{s}\"}}\n", .{
        command.id,
        command.name,
        editor_state.status_buf[0..editor_state.status_len],
    });
}

fn parseRenderMode(value: []const u8) !project_editor_types.ShadingMode {
    if (std.mem.eql(u8, value, "wireframe")) return .wireframe;
    if (std.mem.eql(u8, value, "solid")) return .solid;
    if (std.mem.eql(u8, value, "material_preview")) return .material_preview;
    if (std.mem.eql(u8, value, "lod_debug")) return .lod_debug;
    if (std.mem.eql(u8, value, "rendered")) return .rendered;
    if (std.mem.eql(u8, value, "wire")) return .wireframe;
    if (std.mem.eql(u8, value, "unlit")) return .material_preview;
    if (std.mem.eql(u8, value, "lod")) return .lod_debug;
    if (std.mem.eql(u8, value, "full")) return .rendered;
    if (std.mem.eql(u8, value, "lit")) return .rendered;
    return error.InvalidPropRenderMode;
}

fn parseTextureQuality(value: []const u8) !u8 {
    if (std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "1x")) return 1;
    if (std.mem.eql(u8, value, "2") or std.mem.eql(u8, value, "2x")) return 2;
    if (std.mem.eql(u8, value, "4") or std.mem.eql(u8, value, "4x")) return 4;
    return error.InvalidPropTextureQuality;
}

fn parsePrimitiveKind(value: []const u8) ?shared.geometry.PrimitiveKind {
    if (std.mem.eql(u8, value, "box")) return .box;
    if (std.mem.eql(u8, value, "plane")) return .plane;
    if (std.mem.eql(u8, value, "cylinder")) return .cylinder;
    if (std.mem.eql(u8, value, "sphere")) return .sphere;
    return null;
}

fn parseCommandObject(comptime T: type, allocator: std.mem.Allocator, command: CommandFile) !std.json.Parsed(T) {
    return parseStrictJson(T, allocator, command.object orelse return error.MissingObject);
}

fn parseStrictJson(comptime T: type, allocator: std.mem.Allocator, payload: []const u8) !std.json.Parsed(T) {
    return std.json.parseFromSlice(T, allocator, payload, .{ .ignore_unknown_fields = false });
}

fn parseFloatTuple(payload: []const u8, comptime count: usize) ![count]f32 {
    var result: [count]f32 = undefined;
    var iter = std.mem.splitScalar(u8, payload, ',');
    var idx: usize = 0;
    while (iter.next()) |part| {
        if (idx >= count) return error.InvalidArguments;
        result[idx] = std.fmt.parseFloat(f32, std.mem.trim(u8, part, " \t\r\n")) catch return error.InvalidArguments;
        idx += 1;
    }
    if (idx != count) return error.InvalidArguments;
    return result;
}

fn appendJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(allocator, '"');
    for (value) |ch| switch (ch) {
        '"' => try out.appendSlice(allocator, "\\\""),
        '\\' => try out.appendSlice(allocator, "\\\\"),
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0...8, 11, 12, 14...0x1f => {
            try appendFmt(allocator, out, "\\u{x:0>4}", .{ch});
        },
        else => try out.append(allocator, ch),
    };
    try out.append(allocator, '"');
}

fn appendFmt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const piece = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(piece);
    try out.appendSlice(allocator, piece);
}

test "parseRenderMode accepts canonical values and legacy aliases" {
    try std.testing.expectEqual(project_editor_types.ShadingMode.wireframe, try parseRenderMode("wireframe"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.solid, try parseRenderMode("solid"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.material_preview, try parseRenderMode("material_preview"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.lod_debug, try parseRenderMode("lod_debug"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.rendered, try parseRenderMode("rendered"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.wireframe, try parseRenderMode("wire"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.material_preview, try parseRenderMode("unlit"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.lod_debug, try parseRenderMode("lod"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.rendered, try parseRenderMode("lit"));
    try std.testing.expectEqual(project_editor_types.ShadingMode.rendered, try parseRenderMode("full"));
    try std.testing.expectError(error.InvalidPropRenderMode, parseRenderMode("collision"));
}

test "parsePrimitiveKind accepts explicit shape source seeds" {
    try std.testing.expectEqual(shared.geometry.PrimitiveKind.box, parsePrimitiveKind("box").?);
    try std.testing.expectEqual(shared.geometry.PrimitiveKind.plane, parsePrimitiveKind("plane").?);
    try std.testing.expectEqual(shared.geometry.PrimitiveKind.cylinder, parsePrimitiveKind("cylinder").?);
    try std.testing.expectEqual(shared.geometry.PrimitiveKind.sphere, parsePrimitiveKind("sphere").?);
    try std.testing.expect(parsePrimitiveKind("capsule") == null);
}

test "prop path sketch command records path source gesture" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);

    const out = try execute(std.testing.allocator, .{
        .id = "path-1",
        .name = "prop.sketch-path-point",
        .point_x = 1.25,
        .point_y = 0.5,
        .point_z = -2.0,
    }, &state);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqual(project_editor_types.EditorMode.prop_creation, state.mode);
    try std.testing.expectEqual(project_editor_types.PropTool.edit, state.prop_tool);
    try std.testing.expectEqual(project_editor_types.PropSketchMode.path, state.prop_sketch_mode);
    try std.testing.expectEqual(@as(usize, 1), state.prop_sketch_points.items.len);
    try std.testing.expectEqual(@as(f32, 1.25), state.prop_sketch_points.items[0].x);
    try std.testing.expectEqualStrings("draw_path", @tagName(state.active_gesture.kind));
    try std.testing.expectEqualStrings("committed", @tagName(state.active_gesture.phase));
    try std.testing.expect(std.mem.indexOf(u8, out, "\"points\":1") != null);
}

test "prop sketch point update edits an active shape source point" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
        .prop_sketch_mode = .face,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0, .y = 0, .z = 0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 1, .y = 0, .z = 0 });

    const out = try execute(std.testing.allocator, .{
        .id = "point-update-1",
        .name = "prop.sketch-point-update",
        .vertex = 1,
        .point_x = 2.5,
        .point_z = -0.25,
    }, &state);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqual(project_editor_types.EditorMode.prop_creation, state.mode);
    try std.testing.expectEqual(project_editor_types.PropTool.edit, state.prop_tool);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), state.prop_sketch_points.items[1].x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), state.prop_sketch_points.items[1].y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.25), state.prop_sketch_points.items[1].z, 0.0001);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"vertex\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"x\":2.500000") != null);
}

test "prop sketch operation command updates live operation parameters" {
    var state = ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer state.prop_sketch_points.deinit(std.testing.allocator);

    const out = try execute(std.testing.allocator, .{
        .id = "operation-1",
        .name = "prop.sketch-operation",
        .amount = 0.25,
        .segments = 48,
    }, &state);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqual(project_editor_types.EditorMode.prop_creation, state.mode);
    try std.testing.expectEqual(project_editor_types.PropTool.edit, state.prop_tool);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), state.prop_sketch_amount, 0.0001);
    try std.testing.expectEqual(@as(u32, 48), state.prop_sketch_segments);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"amount\":0.250000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"segments\":48") != null);
}
