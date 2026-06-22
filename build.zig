const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const kdl_dep = b.dependency("kdl", .{
        .target = target,
        .optimize = optimize,
    });
    const zphysics_dep = b.dependency("zphysics", .{
        .target = target,
        .optimize = optimize,
        .use_double_precision = false,
        .enable_cross_platform_determinism = true,
    });
    const engine_mod = b.addModule("friendly_engine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "kdl", .module = kdl_dep.module("kdl") },
            .{ .name = "zphysics", .module = zphysics_dep.module("root") },
        },
    });
    const zgltf_dep = b.dependency("zgltf", .{
        .target = target,
        .optimize = optimize,
    });
    const runtime_shared_mod = b.addModule("runtime_shared", .{
        .root_source_file = b.path("src/runtime/shared/mod.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "friendly_engine", .module = engine_mod },
            .{ .name = "kdl", .module = kdl_dep.module("kdl") },
            .{ .name = "zgltf", .module = zgltf_dep.module("zgltf") },
        },
    });
    addAudioDecode(b, runtime_shared_mod);
    addHarfBuzzShape(b, runtime_shared_mod);
    addXatlas(b, runtime_shared_mod);

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const editor_build_options = b.addOptions();
    editor_build_options.addOption([]const u8, "build_hash", sourceBuildHash(b) catch @panic("failed to compute source build hash"));
    editor_build_options.addOption(bool, "show_build_hash", showNonProdBuildHash(optimize));
    const editor_build_info_mod = editor_build_options.createModule();

    const client_exe = b.addExecutable(.{
        .name = "friendly_engine_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/client/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "friendly_engine", .module = engine_mod },
                .{ .name = "runtime_shared", .module = runtime_shared_mod },
            },
        }),
    });
    client_exe.root_module.linkSystemLibrary("c", .{});
    linkLuaJit(b, client_exe, target);
    linkZphysics(client_exe, zphysics_dep);
    linkSdl3(b, client_exe, target, optimize);
    linkProductionGpu(b, client_exe, target);
    b.installArtifact(client_exe);

    const editor_exe = b.addExecutable(.{
        .name = "friendly_engine_editor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/editor/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "friendly_engine", .module = engine_mod },
                .{ .name = "runtime_shared", .module = runtime_shared_mod },
                .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
                .{ .name = "build_info", .module = editor_build_info_mod },
            },
        }),
    });
    editor_exe.root_module.linkSystemLibrary("c", .{});
    editor_exe.root_module.linkSystemLibrary("freetype2", .{});
    linkZphysics(editor_exe, zphysics_dep);
    addPlutoSvg(b, editor_exe, target);
    linkSdl3(b, editor_exe, target, optimize);
    linkProductionGpu(b, editor_exe, target);
    const editor_os = target.query.os_tag orelse @import("builtin").os.tag;
    if (editor_os == .macos) {
        editor_exe.root_module.addCSourceFile(.{
            .file = b.path("src/runtime/editor/menubar_macos.m"),
            .flags = &.{"-fobjc-arc"},
        });
        editor_exe.root_module.addIncludePath(b.path("src/runtime/editor"));
        editor_exe.root_module.linkFramework("Cocoa", .{});
    } else {
        editor_exe.root_module.addCSourceFile(.{
            .file = b.path("src/runtime/editor/menubar_stub.c"),
        });
    }
    b.installArtifact(editor_exe);

    const gpu_canary_exe = b.addExecutable(.{
        .name = "friendly_engine_gpu_canary",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/canary/gpu_present_canary.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "friendly_engine", .module = engine_mod },
                .{ .name = "runtime_shared", .module = runtime_shared_mod },
            },
        }),
    });
    gpu_canary_exe.root_module.linkSystemLibrary("c", .{});
    linkSdl3(b, gpu_canary_exe, target, optimize);
    linkProductionGpu(b, gpu_canary_exe, target);
    b.installArtifact(gpu_canary_exe);

    const server_exe = b.addExecutable(.{
        .name = "friendly_engine_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/server/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "friendly_engine", .module = engine_mod },
                .{ .name = "runtime_shared", .module = runtime_shared_mod },
                .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            },
        }),
    });
    server_exe.root_module.linkSystemLibrary("c", .{});
    linkZphysics(server_exe, zphysics_dep);
    b.installArtifact(server_exe);

    const tools_exe = b.addExecutable(.{
        .name = "friendly_engine_tools",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "friendly_engine", .module = engine_mod },
                .{ .name = "runtime_shared", .module = runtime_shared_mod },
                .{ .name = "zgltf", .module = zgltf_dep.module("zgltf") },
                .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
            },
        }),
    });
    tools_exe.root_module.linkSystemLibrary("c", .{});
    linkZphysics(tools_exe, zphysics_dep);
    b.installArtifact(tools_exe);

    const mcp_exe = b.addExecutable(.{
        .name = "friendly_engine_mcp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/mcp_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "editor_control_commands",
                    .module = b.createModule(.{
                        .root_source_file = b.path("src/runtime/shared/editor_control_commands.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            },
        }),
    });
    mcp_exe.root_module.linkSystemLibrary("c", .{});
    b.installArtifact(mcp_exe);

    const modcheck_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/modcheck_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const modcheck_exe = b.addExecutable(.{
        .name = "friendly_engine_modcheck",
        .root_module = modcheck_mod,
    });
    b.installArtifact(modcheck_exe);

    const doctor_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/doctor_main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "friendly_engine", .module = engine_mod },
            .{ .name = "runtime_shared", .module = runtime_shared_mod },
        },
    });
    const doctor_exe = b.addExecutable(.{
        .name = "friendly_engine_doctor",
        .root_module = doctor_mod,
    });
    doctor_exe.root_module.linkSystemLibrary("c", .{});
    linkZphysics(doctor_exe, zphysics_dep);
    b.installArtifact(doctor_exe);

    const run_client_step = b.step("run-client", "Run the client runtime");
    const run_step = b.step("run", "Run the client runtime");
    const run_client_cmd = b.addRunArtifact(client_exe);
    if (b.args) |args| {
        run_client_cmd.addArgs(args);
    }
    run_client_step.dependOn(&run_client_cmd.step);
    run_step.dependOn(&run_client_cmd.step);

    const run_editor_step = b.step("run-editor", "Run the editor runtime");
    const run_editor_cmd = b.addRunArtifact(editor_exe);
    if (b.args) |args| {
        run_editor_cmd.addArgs(args);
    }
    run_editor_step.dependOn(&run_editor_cmd.step);

    const run_gpu_canary_step = b.step("run-gpu-canary", "Run the no-asset SDL GPU canary");
    const run_gpu_canary_cmd = b.addRunArtifact(gpu_canary_exe);
    if (b.args) |args| {
        run_gpu_canary_cmd.addArgs(args);
    }
    run_gpu_canary_step.dependOn(&run_gpu_canary_cmd.step);

    const run_server_step = b.step("run-server", "Run the dedicated server runtime");
    const run_server_cmd = b.addRunArtifact(server_exe);
    run_server_step.dependOn(&run_server_cmd.step);

    const run_tools_step = b.step("run-tools", "Run the asset tools CLI");
    const run_tools_cmd = b.addRunArtifact(tools_exe);
    if (b.args) |args| {
        run_tools_cmd.addArgs(args);
    }
    run_tools_step.dependOn(&run_tools_cmd.step);

    const run_mcp_step = b.step("run-mcp", "Run the friendly-engine MCP stdio server");
    const run_mcp_cmd = b.addRunArtifact(mcp_exe);
    if (b.args) |args| {
        run_mcp_cmd.addArgs(args);
    }
    run_mcp_step.dependOn(&run_mcp_cmd.step);

    const bake_step = b.step("bake", "Import assets, bundle, and bake scenes");
    const bake_cmd = b.addRunArtifact(tools_exe);
    bake_cmd.addArg("bake");
    if (b.args) |args| {
        bake_cmd.addArgs(args);
    }
    bake_step.dependOn(&bake_cmd.step);

    const shaders_step = b.step("shaders", "Regenerate runtime SPIR-V shaders from WGSL sources");
    addShaderCompile(b, shaders_step, "TexturedQuadWithMatrix.vert", "vert");
    addShaderCompile(b, shaders_step, "TexturedQuadInstanced.vert", "vert");
    addShaderCompile(b, shaders_step, "TexturedQuad.frag", "frag");
    addShaderCompile(b, shaders_step, "GrassBlade.vert", "vert");
    addShaderCompile(b, shaders_step, "GrassBlade.frag", "frag");
    addShaderCompile(b, shaders_step, "SolidShaded.frag", "frag");
    addShaderCompile(b, shaders_step, "PositionColorTransform.vert", "vert");
    addShaderCompile(b, shaders_step, "Wireframe.vert", "vert");
    addShaderCompile(b, shaders_step, "SolidColor.frag", "frag");
    addShaderCompile(b, shaders_step, "OverlayQuad.vert", "vert");
    addShaderCompile(b, shaders_step, "OverlayQuad.frag", "frag");
    addShaderCompile(b, shaders_step, "OverlayMaskQuad.frag", "frag");
    addShaderCompile(b, shaders_step, "OverlaySdfQuad.frag", "frag");
    addShaderCompile(b, shaders_step, "TexturedQuadLit.frag", "frag");
    addShaderCompile(b, shaders_step, "WaterSurface.frag", "frag");
    addShaderCompile(b, shaders_step, "ShadowDepth.vert", "vert");
    addShaderCompile(b, shaders_step, "ShadowDepthInstanced.vert", "vert");
    addShaderCompile(b, shaders_step, "ShadowDepth.frag", "frag");
    addShaderCompile(b, shaders_step, "Sky.vert", "vert");
    addShaderCompile(b, shaders_step, "Sky.frag", "frag");
    addShaderCompile(b, shaders_step, "Tonemap.frag", "frag");
    addShaderCompile(b, shaders_step, "LuminanceDownsample.frag", "frag");
    const shader_os = target.query.os_tag orelse @import("builtin").os.tag;
    if (shader_os == .macos) {
        addMetalShaderCompile(b, shaders_step, "TexturedQuadWithMatrix.vert");
        addMetalShaderCompile(b, shaders_step, "TexturedQuadInstanced.vert");
        addMetalShaderCompile(b, shaders_step, "TexturedQuad.frag");
        addMetalShaderCompile(b, shaders_step, "GrassBlade.vert");
        addMetalShaderCompile(b, shaders_step, "GrassBlade.frag");
        addMetalShaderCompile(b, shaders_step, "TexturedQuadLit.frag");
        addMetalShaderCompile(b, shaders_step, "WaterSurface.frag");
        addMetalShaderCompile(b, shaders_step, "SolidShaded.frag");
        addMetalShaderCompile(b, shaders_step, "ShadowDepth.vert");
        addMetalShaderCompile(b, shaders_step, "ShadowDepthInstanced.vert");
        addMetalShaderCompile(b, shaders_step, "ShadowDepth.frag");
        addMetalShaderCompile(b, shaders_step, "PositionColorTransform.vert");
        addMetalShaderCompile(b, shaders_step, "Wireframe.vert");
        addMetalShaderCompile(b, shaders_step, "SolidColor.frag");
        addMetalShaderCompile(b, shaders_step, "OverlayQuad.vert");
        addMetalShaderCompile(b, shaders_step, "OverlayQuad.frag");
        addMetalShaderCompile(b, shaders_step, "OverlayMaskQuad.frag");
        addMetalShaderCompile(b, shaders_step, "OverlaySdfQuad.frag");
        addMetalShaderCompile(b, shaders_step, "Sky.vert");
        addMetalShaderCompile(b, shaders_step, "Sky.frag");
        addMetalShaderCompile(b, shaders_step, "Tonemap.frag");
        addMetalShaderCompile(b, shaders_step, "LuminanceDownsample.frag");
    }

    const run_modcheck_step = b.step("modcheck", "Report oversized source modules");
    const run_modcheck_cmd = b.addRunArtifact(modcheck_exe);
    if (b.args) |args| {
        run_modcheck_cmd.addArgs(args);
    }
    run_modcheck_step.dependOn(&run_modcheck_cmd.step);

    const doctor_step = b.step("doctor", "Run tests and LLM-friendly inspections");
    const run_doctor_cmd = b.addRunArtifact(doctor_exe);
    if (b.args) |args| {
        run_doctor_cmd.addArgs(args);
    }
    doctor_step.dependOn(&run_doctor_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = engine_mod });
    mod_tests.root_module.linkSystemLibrary("c", .{});
    linkZphysics(mod_tests, zphysics_dep);
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const shared_tests = b.addTest(.{ .root_module = runtime_shared_mod });
    shared_tests.root_module.linkSystemLibrary("c", .{});
    linkZphysics(shared_tests, zphysics_dep);
    linkSdl3(b, shared_tests, target, optimize);
    linkProductionGpu(b, shared_tests, target);
    const run_shared_tests = b.addRunArtifact(shared_tests);
    const editor_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/runtime/editor/test_root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "friendly_engine", .module = engine_mod },
                .{ .name = "runtime_shared", .module = runtime_shared_mod },
                .{ .name = "zigimg", .module = zigimg_dep.module("zigimg") },
                .{ .name = "build_info", .module = editor_build_info_mod },
            },
        }),
    });
    editor_tests.root_module.linkSystemLibrary("c", .{});
    editor_tests.root_module.linkSystemLibrary("freetype2", .{});
    linkZphysics(editor_tests, zphysics_dep);
    addPlutoSvg(b, editor_tests, target);
    linkSdl3(b, editor_tests, target, optimize);
    linkProductionGpu(b, editor_tests, target);
    if (editor_os == .macos) {
        editor_tests.root_module.addCSourceFile(.{
            .file = b.path("src/runtime/editor/menubar_macos.m"),
            .flags = &.{"-fobjc-arc"},
        });
        editor_tests.root_module.addIncludePath(b.path("src/runtime/editor"));
        editor_tests.root_module.linkFramework("Cocoa", .{});
    } else {
        editor_tests.root_module.addCSourceFile(.{
            .file = b.path("src/runtime/editor/menubar_stub.c"),
        });
    }
    const run_editor_tests = b.addRunArtifact(editor_tests);
    const modcheck_tests = b.addTest(.{ .root_module = modcheck_mod });
    const run_modcheck_tests = b.addRunArtifact(modcheck_tests);
    const doctor_tests = b.addTest(.{ .root_module = doctor_mod });
    const run_doctor_tests = b.addRunArtifact(doctor_tests);
    const mcp_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/mcp_main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "editor_control_commands",
                    .module = b.createModule(.{
                        .root_source_file = b.path("src/runtime/shared/editor_control_commands.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            },
        }),
    });
    mcp_tests.root_module.linkSystemLibrary("c", .{});
    const run_mcp_tests = b.addRunArtifact(mcp_tests);
    const check_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/check_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check_exe = b.addExecutable(.{
        .name = "friendly_engine_check",
        .root_module = check_mod,
    });
    b.installArtifact(check_exe);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_shared_tests.step);
    test_step.dependOn(&run_editor_tests.step);
    test_step.dependOn(&run_modcheck_tests.step);
    test_step.dependOn(&run_doctor_tests.step);
    test_step.dependOn(&run_mcp_tests.step);

    const check_step = b.step("check", "Run LLM-friendly convention checks");
    const run_check_cmd = b.addRunArtifact(check_exe);
    check_step.dependOn(&run_check_cmd.step);

    const fmt_step = b.step("fmt", "Format Zig source files");
    const fmt = b.addFmt(.{ .paths = &.{ "src", "build.zig" } });
    fmt_step.dependOn(&fmt.step);

    const fmt_check_step = b.step("fmt-check", "Check Zig source formatting");
    const fmt_check = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = true,
    });
    fmt_check_step.dependOn(&fmt_check.step);
}

fn linkSdl3(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.linkLibrary(sdl_dep.artifact("SDL3"));
}

fn showNonProdBuildHash(optimize: std.builtin.OptimizeMode) bool {
    return switch (optimize) {
        .Debug, .ReleaseSafe => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
}

fn sourceBuildHash(b: *std.Build) ![]const u8 {
    const allocator = b.allocator;
    const io = b.graph.io;
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }

    try paths.append(allocator, try allocator.dupe(u8, "build.zig"));
    var src_dir = try b.build_root.handle.openDir(io, "src", .{ .iterate = true });
    defer src_dir.close(io);
    var walker = try src_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!hashableSourcePath(entry.path)) continue;
        try paths.append(allocator, try std.fs.path.join(allocator, &.{ "src", entry.path }));
    }
    std.mem.sort([]u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    var hasher = std.hash.Wyhash.init(0);
    for (paths.items) |path| {
        hasher.update(path);
        hasher.update(&.{0});
        const bytes = try b.build_root.handle.readFileAlloc(io, path, allocator, .limited(8 * 1024 * 1024));
        defer allocator.free(bytes);
        hasher.update(bytes);
        hasher.update(&.{0});
    }

    return try std.fmt.allocPrint(allocator, "{x:0>8}", .{@as(u32, @truncate(hasher.final()))});
}

fn hashableSourcePath(path: []const u8) bool {
    const ext = std.fs.path.extension(path);
    return std.mem.eql(u8, ext, ".zig") or
        std.mem.eql(u8, ext, ".c") or
        std.mem.eql(u8, ext, ".h") or
        std.mem.eql(u8, ext, ".m") or
        std.mem.eql(u8, ext, ".wgsl");
}

fn addAudioDecode(b: *std.Build, module: *std.Build.Module) void {
    module.addIncludePath(b.path("third_party/audio"));
    module.addCSourceFile(.{
        .file = b.path("third_party/audio/fe_audio_decode.c"),
        .flags = &.{
            "-std=c99",
            "-DMA_NO_DEVICE_IO",
            "-DMA_NO_ENCODING",
            "-DMA_NO_RESOURCE_MANAGER",
            "-DMA_NO_NODE_GRAPH",
            "-DMA_NO_ENGINE",
        },
    });
    module.addCSourceFile(.{
        .file = b.path("third_party/audio/stb_vorbis.c"),
        .flags = &.{
            "-std=c99",
        },
    });
}

fn addHarfBuzzShape(b: *std.Build, module: *std.Build.Module) void {
    module.addIncludePath(b.path("third_party/text"));
    module.linkSystemLibrary("harfbuzz", .{});
    module.addCSourceFile(.{
        .file = b.path("third_party/text/fe_harfbuzz_shape.c"),
        .flags = &.{
            "-std=c99",
            "-I/opt/homebrew/include/harfbuzz",
            "-I/usr/local/include/harfbuzz",
            "-I/usr/include/harfbuzz",
        },
    });
}

fn addXatlas(b: *std.Build, module: *std.Build.Module) void {
    module.link_libcpp = true;
    module.addIncludePath(b.path("third_party/xatlas"));
    module.addIncludePath(b.path("third_party/xatlas/source/xatlas"));
    module.addCSourceFile(.{
        .file = b.path("third_party/xatlas/fe_xatlas_bridge.cpp"),
        .flags = &.{"-std=c++11"},
    });
    module.addCSourceFile(.{
        .file = b.path("third_party/xatlas/source/xatlas/xatlas.cpp"),
        .flags = &.{"-std=c++11"},
    });
}

fn linkZphysics(exe: *std.Build.Step.Compile, zphysics_dep: *std.Build.Dependency) void {
    exe.root_module.linkLibrary(zphysics_dep.artifact("joltc"));
}

fn linkLuaJit(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const make_luajit = b.addSystemCommand(&.{
        "make",
        "-C",
        "third_party/luajit/src",
        "BUILDMODE=static",
    });
    if (target.result.os.tag == .macos) {
        make_luajit.setEnvironmentVariable("MACOSX_DEPLOYMENT_TARGET", "13.0");
    }
    exe.step.dependOn(&make_luajit.step);
    exe.root_module.addIncludePath(b.path("third_party/luajit/src"));
    exe.root_module.addObjectFile(b.path("third_party/luajit/src/libluajit.a"));
    switch (target.result.os.tag) {
        .linux => {
            exe.root_module.linkSystemLibrary("m", .{});
            exe.root_module.linkSystemLibrary("dl", .{});
        },
        .macos => exe.root_module.linkSystemLibrary("m", .{}),
        else => {},
    }
}

fn addPlutoSvg(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const flags = &.{
        "-std=c99",
        "-DPLUTOVG_BUILD_STATIC",
        "-DPLUTOSVG_BUILD_STATIC",
    };
    exe.root_module.addIncludePath(b.path("third_party/pluto"));
    exe.root_module.addIncludePath(b.path("third_party/pluto/plutosvg"));
    exe.root_module.addIncludePath(b.path("third_party/pluto/plutovg"));
    if (target.result.os.tag == .linux) {
        exe.root_module.linkSystemLibrary("m", .{});
    }
    exe.root_module.addCSourceFile(.{ .file = b.path("third_party/pluto/fe_plutosvg_bridge.c"), .flags = flags });
    exe.root_module.addCSourceFile(.{ .file = b.path("third_party/pluto/plutosvg/plutosvg.c"), .flags = flags });
    inline for (.{
        "plutovg-blend.c",
        "plutovg-canvas.c",
        "plutovg-font.c",
        "plutovg-ft-math.c",
        "plutovg-ft-raster.c",
        "plutovg-ft-stroker.c",
        "plutovg-matrix.c",
        "plutovg-paint.c",
        "plutovg-path.c",
        "plutovg-rasterize.c",
        "plutovg-surface.c",
    }) |source| {
        exe.root_module.addCSourceFile(.{
            .file = b.path("third_party/pluto/plutovg/" ++ source),
            .flags = flags,
        });
    }
}

fn linkProductionGpu(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    const os = target.result.os.tag;
    switch (os) {
        .macos => {
            exe.root_module.linkFramework("Metal", .{});
            exe.root_module.linkFramework("QuartzCore", .{});
        },
        .linux => exe.root_module.linkSystemLibrary("vulkan", .{}),
        else => {},
    }
    _ = b;
}

fn addShaderCompile(
    b: *std.Build,
    step: *std.Build.Step,
    comptime name: []const u8,
    comptime stage: []const u8,
) void {
    const cmd = b.addSystemCommand(&.{
        "naga",
        "--input-kind",
        "wgsl",
        "--shader-stage",
        stage,
        "--entry-point",
        "main",
        "src/runtime/shared/shaders/source/" ++ name ++ ".wgsl",
        "src/runtime/shared/shaders/spirv/" ++ name ++ ".spv",
    });
    step.dependOn(&cmd.step);
}

fn addMetalShaderCompile(
    b: *std.Build,
    step: *std.Build.Step,
    comptime name: []const u8,
) void {
    const metal_path = "src/runtime/shared/shaders/metal/" ++ name ++ ".metal";
    const compile_cmd = b.addSystemCommand(&.{
        "naga",
        "--input-kind",
        "wgsl",
        "--entry-point",
        "main",
        "src/runtime/shared/shaders/source/" ++ name ++ ".wgsl",
        metal_path,
    });
    step.dependOn(&compile_cmd.step);

    const validate_cmd = b.addSystemCommand(&.{
        "sh",
        "scripts/validate-msl.sh",
        metal_path,
        ".zig-cache/shaders/msl/" ++ name ++ ".air",
    });
    validate_cmd.step.dependOn(&compile_cmd.step);
    step.dependOn(&validate_cmd.step);
}
