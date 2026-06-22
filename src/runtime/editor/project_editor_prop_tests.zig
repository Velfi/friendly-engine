const std = @import("std");
const shared = @import("runtime_shared");
const project_editor_prop = @import("project_editor_prop.zig");
const project_editor_prop_asset = @import("project_editor_prop_asset.zig");
const project_editor_asset_browser = @import("project_editor_asset_browser.zig");
const project_editor_state = @import("project_editor_state.zig");
const project_editor_texture_paint = @import("project_editor_texture_paint.zig");
const SceneObject = @import("editor_scene_object.zig").SceneObject;
const geometry = shared.geometry;
const editor_math = shared.editor_math;

test "prop catalog maps crate_wood to imported box mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestAssetManifest(tmp.dir, "assets/source/meshes/box.glb", "mesh");
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    var catalog = project_editor_asset_browser.load(
        std.testing.allocator,
        std.testing.io,
        project_path,
        project_editor_prop.cache_target,
    ) catch return error.SkipZigTest;
    defer catalog.deinit(std.testing.allocator);

    const entry = project_editor_prop.findCatalogEntry("crate_wood").?;
    try std.testing.expect(catalog.hasImportedMesh(entry.mesh_ref));
}

test "prop catalog props are absent until mesh assets are imported" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestAssetManifest(tmp.dir, "assets/source/meshes/box.glb", "mesh");
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);

    var catalog = project_editor_asset_browser.load(
        std.testing.allocator,
        std.testing.io,
        project_path,
        project_editor_prop.cache_target,
    ) catch return error.SkipZigTest;
    defer catalog.deinit(std.testing.allocator);

    const entry = project_editor_prop.findCatalogEntry("lamp_wall").?;
    try std.testing.expect(!catalog.hasImportedMesh(entry.mesh_ref));
}

test "recordRecentProp deduplicates and caps recent list" {
    var state = project_editor_state.ProjectEditorState{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = "",
        .project_name = "",
        .objects = .empty,
    };
    defer {
        for (state.prop_recent_ids.items) |id| std.testing.allocator.free(id);
        state.prop_recent_ids.deinit(std.testing.allocator);
    }

    project_editor_prop.recordRecentProp(&state, "crate_wood");
    project_editor_prop.recordRecentProp(&state, "lamp_wall");
    project_editor_prop.recordRecentProp(&state, "crate_wood");
    try std.testing.expectEqual(@as(usize, 2), state.prop_recent_ids.items.len);
    try std.testing.expectEqualStrings("crate_wood", state.prop_recent_ids.items[0]);
    try std.testing.expectEqualStrings("lamp_wall", state.prop_recent_ids.items[1]);

    for (0..project_editor_prop.max_recent_props + 2) |i| {
        var buf: [32]u8 = undefined;
        const id = std.fmt.bufPrint(&buf, "prop-{d}", .{i}) catch continue;
        project_editor_prop.recordRecentProp(&state, id);
    }
    try std.testing.expectEqual(project_editor_prop.max_recent_props, state.prop_recent_ids.items.len);
}

test "setGameplayTag trims and updates selected prop gameplay tag" {
    var state = try testState();
    defer state.deinit();
    try appendTestProp(&state, "prop");
    state.selected_object = 0;

    try project_editor_prop.setGameplayTag(&state, "  switch_panel \n");

    try std.testing.expect(state.scene_dirty);
    try std.testing.expectEqualStrings("switch_panel", state.objects.items[0].gameplay.?.tag);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
}

test "setGameplayTag rejects empty selected prop tag" {
    var state = try testState();
    defer state.deinit();
    try appendTestProp(&state, "prop");
    state.selected_object = 0;

    try std.testing.expectError(error.EmptyGameplayTag, project_editor_prop.setGameplayTag(&state, " \t\n"));
    try std.testing.expect(state.objects.items[0].gameplay == null);
    try std.testing.expect(!state.scene_dirty);
}

test "prop primitive ramp creates an editable sloped mesh" {
    var state = try testState();
    defer state.deinit();
    state.mode = .prop_creation;

    try project_editor_prop.addPrimitiveProp(&state, .ramp);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    const ramp = &state.objects.items[0];
    try std.testing.expectEqual(@as(?geometry.PrimitiveKind, null), ramp.primitive_kind);
    try std.testing.expectEqual(@as(usize, 18), ramp.mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 24), ramp.mesh.indices.len);
    try std.testing.expectEqual(@as(?usize, 0), state.selected_object);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ramp.position.y, 0.001);
    try expectMeshTrianglesMatchVertexNormals(&ramp.mesh);
}

test "prop primitive placement honors selected primitive shape" {
    var state = try testState();
    defer state.deinit();
    state.mode = .prop_creation;

    try project_editor_prop.placePrimitiveProp(&state, .{ .x = 2, .y = 0, .z = -1 }, .cylinder);

    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    const cylinder = &state.objects.items[0];
    try std.testing.expectEqual(geometry.PrimitiveKind.cylinder, cylinder.primitive_kind.?);
    try std.testing.expect(cylinder.mesh.vertices.len > 24);
    try std.testing.expectApproxEqAbs(@as(f32, 2), cylinder.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), cylinder.position.z, 0.001);
    try expectMeshTrianglesMatchVertexNormals(&cylinder.mesh);
}

test "prop primitive cube uses world texel density" {
    var state = try testState();
    defer state.deinit();
    state.mode = .prop_creation;

    try project_editor_prop.placePrimitiveProp(&state, .{ .x = 0, .y = 0, .z = 0 }, .cube);

    const cube = &state.objects.items[0];
    try geometry.validateUniformTexelDensity(&cube.mesh, 128.0, 128.0, 0.001);
}

test "prop asset geometry save keeps generated tiled uvs until paint unwrap" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    try appendTestPropAsset(&state, "wide prop", "wide_box");
    state.selected_object = 0;
    state.objects.items[0].mesh.deinit(state.allocator);
    state.objects.items[0].mesh = try geometry.buildPrimitive(state.allocator, .box, .{ .width = 3, .height = 1, .depth = 1 });

    try project_editor_prop.propagateSelectedAssetGeometryFallible(&state);

    const bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/meshes/wide_box.fmesh", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(bytes);
    var saved_mesh = try shared.mesh_codec.decodeMesh(std.testing.allocator, bytes);
    defer saved_mesh.deinit(std.testing.allocator);
    var has_tiled_uv = false;
    for (saved_mesh.vertices) |vertex| {
        has_tiled_uv = has_tiled_uv or vertex.uv.x > 1.0 or vertex.uv.y > 1.0;
    }
    try std.testing.expect(has_tiled_uv);
    try geometry.validateUniformTexelDensity(&saved_mesh, 128.0, 128.0, 0.001);
}

test "openAssetForEditing creates editor-only working copy separate from scene instances" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    try appendTestPropAsset(&state, "crate", "crate_wood");
    try appendTestPropAsset(&state, "lamp", "lamp_wall");

    try project_editor_prop.openAssetForEditing(&state, "lamp_wall");

    try std.testing.expectEqual(@as(?usize, 2), state.selected_object);
    try std.testing.expectEqual(.select, state.prop_tool);
    try std.testing.expectEqualStrings("lamp_wall", state.active_prop_asset_id.?);
    try std.testing.expectEqualStrings("lamp_wall", state.prop_selected_asset);
    try std.testing.expectEqual(@as(usize, 3), state.objects.items.len);
    try std.testing.expect(!state.objects.items[1].editor_only);
    try std.testing.expect(state.objects.items[2].editor_only);
}

test "openAssetForEditing reopens project prop asset with saved shape intent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();

    try project_editor_prop_asset.createCustomAssetWorkingCopy(&state, "user_seed", "User Seed", "shape");
    try project_editor_prop_asset.appendPrimitiveSeedSelected(&state, .cylinder, .{ .radius = 0.35, .height = 1.4, .segments = 12 });
    for (state.objects.items) |*obj| obj.deinit(state.allocator);
    state.objects.clearRetainingCapacity();
    state.selected_object = null;

    try project_editor_prop.openAssetForEditing(&state, "user_seed");

    try std.testing.expectEqual(@as(?usize, 0), state.selected_object);
    try std.testing.expectEqual(.select, state.prop_tool);
    try std.testing.expectEqual(.display, state.prop_workspace_mode);
    try std.testing.expectEqualStrings("user_seed", state.active_prop_asset_id.?);
    try std.testing.expectEqual(@as(usize, 1), state.objects.items.len);
    try std.testing.expect(state.objects.items[0].editor_only);
    try std.testing.expectEqualStrings("user_seed", state.objects.items[0].prop_asset_id.?);
    try std.testing.expect(state.objects.items[0].mesh.vertices.len > 0);

    var doc = try project_editor_prop_asset.loadAssetDocument(&state, "user_seed");
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.primitive_seed, doc.recipe.shape_intents[0].source_kind);
}

test "open prop asset failure stores copyable error detail" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();

    try project_editor_prop.setOpenAssetErrorDetail(&state, "missing_prop", error.MissingPropAssetMesh, null);

    try std.testing.expectEqualStrings("Open Prop Failed", state.editor_error_title.?);
    const detail = state.editor_error_detail.?;
    try std.testing.expect(std.mem.indexOf(u8, detail, "Open Prop Asset failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "- selected asset: missing_prop") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, project_path) != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "- error: MissingPropAssetMesh") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "Zig error return trace:") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "(unavailable in this build)") != null);
}

test "prop asset geometry propagation preserves instance transform and tint" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "crate source", "crate_wood");
    try appendTestPropAsset(&state, "crate instance", "crate_wood");
    state.selected_object = 0;
    state.objects.items[1].position = .{ .x = 4, .y = 2, .z = -3 };
    state.objects.items[1].scale = .{ .x = 2, .y = 1, .z = 0.5 };
    state.objects.items[1].base_color = .{ .r = 20, .g = 40, .b = 220, .a = 255 };

    state.objects.items[0].mesh.vertices[0].position.x += 2.0;
    project_editor_prop.propagateSelectedAssetGeometry(&state);

    try std.testing.expectApproxEqAbs(
        state.objects.items[0].mesh.vertices[0].position.x,
        state.objects.items[1].mesh.vertices[0].position.x,
        0.0001,
    );
    try std.testing.expectEqual(@as(f32, 4), state.objects.items[1].position.x);
    try std.testing.expectEqual(@as(f32, 2), state.objects.items[1].scale.x);
    try std.testing.expectEqual(@as(u8, 20), state.objects.items[1].base_color.r);
}

test "regenerateSelectedFromRecipe rebuilds every instance of the prop asset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "crate source", "crate_wood");
    try appendTestPropAsset(&state, "crate instance", "crate_wood");
    state.selected_object = 0;

    try project_editor_prop.regenerateSelectedFromRecipe(&state);

    const source_bounds = meshBounds(&state.objects.items[0].mesh);
    const instance_bounds = meshBounds(&state.objects.items[1].mesh);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), source_bounds.max.x - source_bounds.min.x, 0.0001);
    try std.testing.expectApproxEqAbs(source_bounds.max.x, instance_bounds.max.x, 0.0001);
    try std.testing.expect(state.objects.items[0].primitive_kind == null);
    try std.testing.expect(state.objects.items[1].primitive_kind == null);
}

test "procedural array operation updates every prop instance mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "crate source", "crate_wood");
    try appendTestPropAsset(&state, "crate instance", "crate_wood");
    state.selected_object = 0;
    const before_vertices = state.objects.items[1].mesh.vertices.len;

    try project_editor_prop.arraySelectedX(&state);

    try std.testing.expectEqual(before_vertices * 2, state.objects.items[0].mesh.vertices.len);
    try std.testing.expectEqual(before_vertices * 2, state.objects.items[1].mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/crate_wood.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(doc_bytes);
    var doc = try shared.prop_asset_doc.parse(std.testing.allocator, doc_bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    const intent = doc.recipe.shape_intents[0];
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.existing_mesh, intent.source_kind);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeOperationKind.array, intent.operation_kind);
    try std.testing.expectEqual(@as(u32, 2), intent.segments);
    try std.testing.expect(intent.amount > 0);
}

test "procedural mirror operation persists existing mesh operation intent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "crate source", "crate_wood");
    try appendTestPropAsset(&state, "crate instance", "crate_wood");
    state.selected_object = 0;
    const before_vertices = state.objects.items[1].mesh.vertices.len;

    try project_editor_prop.mirrorSelectedX(&state);

    try std.testing.expectEqual(before_vertices * 2, state.objects.items[0].mesh.vertices.len);
    try std.testing.expectEqual(before_vertices * 2, state.objects.items[1].mesh.vertices.len);
    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/crate_wood.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(doc_bytes);
    var doc = try shared.prop_asset_doc.parse(std.testing.allocator, doc_bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    const intent = doc.recipe.shape_intents[0];
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.existing_mesh, intent.source_kind);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeOperationKind.mirror, intent.operation_kind);
}

test "solidify operation adds thickness and updates every prop instance mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "source", "user_panel");
    try appendTestPropAsset(&state, "instance", "user_panel");
    state.selected_object = 0;
    state.objects.items[0].mesh.deinit(std.testing.allocator);
    state.objects.items[0].mesh = try geometry.buildPrimitive(std.testing.allocator, .plane, .{ .width = 1, .depth = 1 });
    const before_vertices = state.objects.items[0].mesh.vertices.len;

    try project_editor_prop.solidifySelected(&state, 0.1);

    try std.testing.expect(state.objects.items[0].mesh.vertices.len > before_vertices);
    try std.testing.expectEqual(state.objects.items[0].mesh.vertices.len, state.objects.items[1].mesh.vertices.len);
    try expectMeshTrianglesMatchVertexNormals(&state.objects.items[0].mesh);
    try expectMeshTrianglesMatchVertexNormals(&state.objects.items[1].mesh);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
}

test "solidify operation turns face sketch into prop geometry" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    state.prop_sketch_mode = .face;
    try appendTestPropAsset(&state, "source", "user_panel");
    try appendTestPropAsset(&state, "instance", "user_panel");
    state.selected_object = 0;
    const before_vertices = state.objects.items[0].mesh.vertices.len;
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = -0.2, .y = 0.1, .z = -0.2 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0.2, .y = 0.1, .z = -0.2 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0.2, .y = 0.4, .z = -0.2 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = -0.2, .y = 0.4, .z = -0.2 });

    try project_editor_prop.solidifySelected(&state, 0.1);

    try std.testing.expect(state.objects.items[0].mesh.vertices.len > before_vertices);
    try std.testing.expectEqual(state.objects.items[0].mesh.vertices.len, state.objects.items[1].mesh.vertices.len);
    try expectMeshTrianglesMatchVertexNormals(&state.objects.items[0].mesh);
    try expectMeshTrianglesMatchVertexNormals(&state.objects.items[1].mesh);
    try std.testing.expectEqual(@as(usize, 0), state.prop_sketch_points.items.len);
    try std.testing.expectEqual(.none, state.prop_sketch_mode);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/user_panel.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(doc_bytes);
    var doc = try shared.prop_asset_doc.parse(std.testing.allocator, doc_bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.closed_face, doc.recipe.shape_intents[0].source_kind);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeOperationKind.solidify, doc.recipe.shape_intents[0].operation_kind);
    try std.testing.expectEqual(@as(usize, 4), doc.recipe.shape_intents[0].points.len);
}

test "primitive seed operation persists source intent metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "source", "user_seed");
    state.selected_object = 0;

    try project_editor_prop_asset.appendPrimitiveSeedSelected(&state, .cylinder, .{ .radius = 0.35, .height = 1.4, .segments = 12 });

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/user_seed.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(doc_bytes);
    var doc = try shared.prop_asset_doc.parse(std.testing.allocator, doc_bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    const intent = doc.recipe.shape_intents[0];
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.primitive_seed, intent.source_kind);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeOperationKind.extrude, intent.operation_kind);
    try std.testing.expectEqual(geometry.PrimitiveKind.cylinder, intent.primitive_kind);
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), intent.primitive_params.radius, 0.001);
    try std.testing.expectEqual(@as(u32, 12), intent.primitive_params.segments);
    try std.testing.expectEqual(@as(usize, 0), intent.points.len);
    try std.testing.expectEqual(.none, state.prop_sketch_mode);
    try std.testing.expect(!state.selected_shape_source);
    try std.testing.expect(!state.selected_shape_operation);
}

test "path extrude operation persists path source intent metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    state.prop_sketch_mode = .path;
    try appendTestPropAsset(&state, "source", "user_rail");
    state.selected_object = 0;
    try state.prop_sketch_points.appendSlice(state.allocator, &.{
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 0, .z = 1 },
        .{ .x = 1, .y = 0.25, .z = 1 },
    });

    try project_editor_prop_asset.extrudePathSelected(&state, 0.2);

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/user_rail.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(doc_bytes);
    var doc = try shared.prop_asset_doc.parse(std.testing.allocator, doc_bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    const intent = doc.recipe.shape_intents[0];
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.path, intent.source_kind);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeOperationKind.extrude, intent.operation_kind);
    try std.testing.expectEqual(@as(usize, 3), intent.points.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), intent.amount, 0.001);
    try std.testing.expectEqual(.none, state.prop_sketch_mode);
    try std.testing.expect(!state.selected_shape_source);
    try std.testing.expect(!state.selected_shape_operation);
}

test "revolve operation creates a lathed prop mesh and updates every instance" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "source", "user_vase");
    try appendTestPropAsset(&state, "instance", "user_vase");
    state.selected_object = 0;

    try project_editor_prop.revolveSelected(&state);

    try std.testing.expect(state.objects.items[0].mesh.vertices.len >= 120);
    try std.testing.expectEqual(state.objects.items[0].mesh.vertices.len, state.objects.items[1].mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);
}

test "revolve operation turns profile sketch into prop geometry" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    state.prop_sketch_mode = .curve;
    state.prop_sketch_segments = 12;
    try appendTestPropAsset(&state, "source", "user_vase");
    try appendTestPropAsset(&state, "instance", "user_vase");
    state.selected_object = 0;
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0.25, .y = 0, .z = 0.0 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0.5, .y = 0, .z = 0.6 });
    try state.prop_sketch_points.append(std.testing.allocator, .{ .x = 0.2, .y = 0, .z = 1.2 });

    try project_editor_prop.revolveSelected(&state);

    try std.testing.expectEqual(@as(usize, 36), state.objects.items[0].mesh.vertices.len);
    try std.testing.expectEqual(state.objects.items[0].mesh.vertices.len, state.objects.items[1].mesh.vertices.len);
    try std.testing.expectEqual(@as(usize, 0), state.prop_sketch_points.items.len);
    try std.testing.expectEqual(.none, state.prop_sketch_mode);
    try std.testing.expectEqual(@as(usize, 1), state.undo_stack.items.len);

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/user_vase.kdl", std.testing.allocator, .limited(8192));
    defer std.testing.allocator.free(doc_bytes);
    var doc = try shared.prop_asset_doc.parse(std.testing.allocator, doc_bytes);
    defer doc.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), doc.recipe.shape_intents.len);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeSourceKind.open_profile, doc.recipe.shape_intents[0].source_kind);
    try std.testing.expectEqual(shared.prop_asset_doc.ShapeOperationKind.revolve, doc.recipe.shape_intents[0].operation_kind);
    try std.testing.expectEqual(@as(u32, 12), doc.recipe.shape_intents[0].segments);
    try std.testing.expectEqual(@as(usize, 3), doc.recipe.shape_intents[0].points.len);
}

test "prop asset geometry edit persists to prop document and shared mesh" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    state.mode = .prop_creation;
    try appendTestPropAsset(&state, "crate source", "crate_wood");
    state.selected_object = 0;
    try ensureTestPaintAtlas(&state, 0);

    state.objects.items[0].mesh.vertices[0].position.x = 9.0;
    try project_editor_prop.propagateSelectedAssetGeometryFallible(&state);

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/crate_wood.kdl", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(doc_bytes);
    try std.testing.expect(std.mem.indexOf(u8, doc_bytes, "id=\"crate_wood\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, doc_bytes, "mesh asset=\"props/meshes/crate_wood.fmesh\"") != null);

    const mesh_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/meshes/crate_wood.fmesh", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(mesh_bytes);
    var mesh = try shared.mesh_codec.decodeMesh(std.testing.allocator, mesh_bytes);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 9.0), mesh.vertices[0].position.x, 0.0001);
}

test "saving editor scene persists prop asset before scene references it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    try appendTestPropAsset(&state, "prop instance", "user_column");
    try ensureTestPaintAtlas(&state, 0);
    state.objects.items[0].base_color = .{ .r = 24, .g = 80, .b = 180, .a = 255 };
    state.objects.items[0].mesh.vertices[0].position.x = 4.5;

    try state.saveSceneToDisk();

    const scene_bytes = try tmp.dir.readFileAlloc(std.testing.io, shared.scene_io.default_scene_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(scene_bytes);
    try std.testing.expect(std.mem.indexOf(u8, scene_bytes, "mesh asset=\"props/meshes/user_column.fmesh\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, scene_bytes, "prop_asset=\"user_column\"") != null);
    try std.testing.expectError(error.FileNotFound, tmp.dir.access(std.testing.io, "scenes/meshes/1.fmesh", .{}));

    const doc_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/user_column.kdl", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(doc_bytes);
    try std.testing.expect(std.mem.indexOf(u8, doc_bytes, "id=\"user_column\"") != null);

    const mesh_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/meshes/user_column.fmesh", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(mesh_bytes);
    var mesh = try shared.mesh_codec.decodeMesh(std.testing.allocator, mesh_bytes);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), mesh.vertices[0].position.x, 0.0001);
}

test "saving editor scene excludes prop editor working copies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeTestDefaultTexture(tmp.dir);
    const project_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(project_path);
    var state = try testStateAt(project_path);
    defer state.deinit();
    try appendTestProp(&state, "world box");
    try appendTestPropAsset(&state, "prop working copy", "user_column");
    try ensureTestPaintAtlas(&state, 1);
    state.objects.items[1].editor_only = true;
    state.objects.items[1].mesh.vertices[0].position.x = 4.5;

    try state.saveSceneToDisk();

    const scene_bytes = try tmp.dir.readFileAlloc(std.testing.io, shared.scene_io.default_scene_path, std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(scene_bytes);
    try std.testing.expect(std.mem.indexOf(u8, scene_bytes, "prop working copy") == null);
    try std.testing.expect(std.mem.indexOf(u8, scene_bytes, "prop_asset=\"user_column\"") == null);

    const mesh_bytes = try tmp.dir.readFileAlloc(std.testing.io, "props/meshes/user_column.fmesh", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(mesh_bytes);
    var mesh = try shared.mesh_codec.decodeMesh(std.testing.allocator, mesh_bytes);
    defer mesh.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 4.5), mesh.vertices[0].position.x, 0.0001);
}

fn testState() !project_editor_state.ProjectEditorState {
    return try testStateAt("");
}

fn writeTestDefaultTexture(dir: std.Io.Dir) !void {
    try dir.createDirPath(std.testing.io, "assets/cache/" ++ project_editor_prop.cache_target ++ "/textures");
    var pixels: [shared.scene_binary.texture_pixel_bytes]u8 = undefined;
    @memset(&pixels, 255);
    try dir.writeFile(std.testing.io, .{
        .sub_path = "assets/cache/" ++ project_editor_prop.cache_target ++ "/textures/default.rgba",
        .data = &pixels,
    });
}

fn writeTestAssetManifest(dir: std.Io.Dir, source_path: []const u8, kind: []const u8) !void {
    try dir.createDirPath(std.testing.io, "assets/cache/" ++ project_editor_prop.cache_target);
    const manifest = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"assets":[{{"asset_id":1,"source_path":"{s}","artifact_path":"assets/cache/{s}/artifact.bin","kind":"{s}","runtime_size_bytes":64}}]}}
        \\
    , .{ source_path, project_editor_prop.cache_target, kind });
    defer std.testing.allocator.free(manifest);
    try dir.writeFile(std.testing.io, .{
        .sub_path = "assets/cache/" ++ project_editor_prop.cache_target ++ "/asset_manifest.json",
        .data = manifest,
    });
}

fn testStateAt(project_path: []const u8) !project_editor_state.ProjectEditorState {
    return .{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_path = try std.testing.allocator.dupe(u8, project_path),
        .project_name = try std.testing.allocator.dupe(u8, ""),
        .active_scene_path = shared.scene_io.default_scene_path,
        .objects = .empty,
    };
}

fn appendTestProp(state: *project_editor_state.ProjectEditorState, name: []const u8) !void {
    try state.objects.append(state.allocator, .{
        .id = 1,
        .name = try state.allocator.dupe(u8, name),
        .mesh = try geometry.buildPrimitive(state.allocator, .box, .{ .width = 1, .height = 1, .depth = 1 }),
        .position = .{ .x = 0, .y = 0, .z = 0 },
        .scale = .{ .x = 1, .y = 1, .z = 1 },
        .texture = &.{},
        .base_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .primitive_kind = .box,
    });
}

// Generating the paint atlas can reorder/duplicate mesh vertices (xatlas chart
// packing), so tests that mutate a specific vertex index and then expect it to
// survive a save/reload round trip must establish the atlas first, before the
// mutation, the same way a real prop asset would have one already by the time
// it's edited again.
fn ensureTestPaintAtlas(state: *project_editor_state.ProjectEditorState, idx: usize) !void {
    if (!project_editor_texture_paint.ensurePaintAtlas(state, &state.objects.items[idx])) return error.InvalidPaintAtlas;
}

fn appendTestPropAsset(state: *project_editor_state.ProjectEditorState, name: []const u8, asset_id: []const u8) !void {
    try appendTestProp(state, name);
    state.objects.items[state.objects.items.len - 1].id = @intCast(state.objects.items.len);
    state.objects.items[state.objects.items.len - 1].prop_asset_id = try state.allocator.dupe(u8, asset_id);
}

fn expectMeshTrianglesMatchVertexNormals(mesh: *const geometry.Mesh) !void {
    var checked: usize = 0;
    var tri: usize = 0;
    while (tri + 2 < mesh.indices.len) : (tri += 3) {
        const v0 = mesh.vertices[mesh.indices[tri]];
        const v1 = mesh.vertices[mesh.indices[tri + 1]];
        const v2 = mesh.vertices[mesh.indices[tri + 2]];
        const face_normal = editor_math.Vec3.normalized(editor_math.cross(
            editor_math.Vec3.sub(v1.position, v0.position),
            editor_math.Vec3.sub(v2.position, v0.position),
        ));
        const vertex_normal = editor_math.Vec3.normalized(editor_math.Vec3.add(editor_math.Vec3.add(v0.normal, v1.normal), v2.normal));
        try std.testing.expect(editor_math.Vec3.dot(face_normal, vertex_normal) > 0.5);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}

fn meshBounds(mesh: *const geometry.Mesh) struct { min: shared.editor_math.Vec3, max: shared.editor_math.Vec3 } {
    var min = mesh.vertices[0].position;
    var max = mesh.vertices[0].position;
    for (mesh.vertices[1..]) |vert| {
        min.x = @min(min.x, vert.position.x);
        min.y = @min(min.y, vert.position.y);
        min.z = @min(min.z, vert.position.z);
        max.x = @max(max.x, vert.position.x);
        max.y = @max(max.y, vert.position.y);
        max.z = @max(max.z, vert.position.z);
    }
    return .{ .min = min, .max = max };
}
