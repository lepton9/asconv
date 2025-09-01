const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Static or dynamic linkage") orelse .static;
    const CFlags = &[_][]const u8{"-fPIC"};

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Exec
    const exec_mod = b.createModule(.{
        .root_source_file = b.path("src/exec.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("exec", exec_mod);

    // Config
    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("config", config_mod);

    // Usage
    const usage_mod = b.createModule(.{
        .root_source_file = b.path("src/usage.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("usage", usage_mod);

    // Cli
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("cli", cli_mod);
    exec_mod.addImport("cli", cli_mod);
    usage_mod.addImport("cli", cli_mod);
    const cli_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cli",
        .root_module = cli_mod,
    });
    b.installArtifact(cli_lib);

    // Core
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("core", core_mod);
    const core_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "core",
        .root_module = core_mod,
    });
    b.installArtifact(core_lib);

    // Image
    const img_mod = b.createModule(.{
        .root_source_file = b.path("src/img.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("img", img_mod);
    img_mod.addImport("core", core_mod);
    });

    // Result
    const result_mod = b.createModule(.{
        .root_source_file = b.path("src/result.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_mod.addImport("result", result_mod);
    exe_mod.addImport("result", result_mod);
    exec_mod.addImport("result", result_mod);
    const result_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "result",
        .root_module = result_mod,
    });
    b.installArtifact(result_lib);

    // Utils
    const utils_mod = b.createModule(.{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_mod.addImport("utils", utils_mod);
    exe_mod.addImport("utils", utils_mod);
    exec_mod.addImport("utils", utils_mod);
    cli_mod.addImport("utils", utils_mod);

    // Stb
    const stb_mod = b.addModule("stb", .{
        .root_source_file = b.path("src/stb.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const stb_dep = b.dependency("stb", .{ .target = target, .optimize = optimize });
    stb_mod.addIncludePath(stb_dep.path(""));
    stb_mod.addIncludePath(b.path("lib"));
    stb_mod.addCSourceFile(.{ .file = b.path("lib/stb.c"), .flags = CFlags });
    img_mod.addImport("stb", stb_mod);
    const stb_lib = b.addLibrary(.{
        .name = "stb",
        .root_module = stb_mod,
        .linkage = linkage,
    });
    stb_lib.installHeadersDirectory(b.path("lib"), "", .{});
    b.installArtifact(stb_lib);

    // Toml
    const toml = b.dependency("toml", .{ .target = target, .optimize = optimize });
    const toml_mod = toml.module("toml");
    config_mod.addImport("toml", toml_mod);

    // Build executable
    const exe = b.addExecutable(.{
        .name = "asconv",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Tests
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/tests.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    tests.root_module.addImport("cli", cli_mod);
    tests.root_module.addImport("exec", exec_mod);
    const run_test_cmd = b.addRunArtifact(tests);
    run_test_cmd.step.dependOn(b.getInstallStep());

    // Allows to add params to program when building: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test_cmd.step);
}
