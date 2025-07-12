const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_compress = b.createModule(.{
        .root_source_file = b.path("src/compress.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This is what allows Zig source code to use `@import("compress")`
    exe_mod.addImport("compress", lib_compress);

    // Create a static library
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "asconv",
        .root_module = lib_compress,
    });
    b.installArtifact(lib);

    // Build executable
    const exe = b.addExecutable(.{
        .name = "asconv",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allows to add params to program when building: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
