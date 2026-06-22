const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Options
    const build_zkdl = b.option(bool, "zkdl", "Build the zkdl utility") orelse false;
    const build_spec_test = b.option(bool, "spec", "Build the specification test suite runner") orelse false;
    const use_llvm = b.option(bool, "llvm", "Use llvm backend");

    // Steps
    const run_step = b.step("run", "Run the executable");
    const docs_step = b.step("docs", "Build documentation");
    const test_step = b.step("test", "Run builtin tests (does not include spec tests)");
    const check_step = b.step("check", "Check the code compiles");

    const mod = b.addModule("kdl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe_spec_test = b.addExecutable(.{
        .name = "kdl-spec-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "kdl", .module = mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    check_step.dependOn(&exe_spec_test.step);

    const exe_zkdl = b.addExecutable(.{
        .name = "kdl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "kdl", .module = mod },
            },
        }),
        .use_llvm = use_llvm,
    });
    check_step.dependOn(&exe_zkdl.step);

    if (build_zkdl) {
        b.installArtifact(exe_zkdl);

        const run_cmd = b.addRunArtifact(exe_zkdl);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    } else if (build_spec_test) {
        b.installArtifact(exe_spec_test);

        const run_cmd = b.addRunArtifact(exe_spec_test);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    } else {
        const fail = b.addFail("Cannot run executable without passing -Dzkdl");
        run_step.dependOn(&fail.step);
    }

    const lib_tests = b.addTest(.{
        .root_module = mod,
    });
    check_step.dependOn(&lib_tests.step);

    const run_lib_tests = b.addRunArtifact(lib_tests);
    test_step.dependOn(&run_lib_tests.step);

    // Docs
    const docs = b.addLibrary(.{ .name = "kdl", .root_module = mod });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
