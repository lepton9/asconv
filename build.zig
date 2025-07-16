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

    // Cli
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("cli", cli_mod);
    const cli_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cli",
        .root_module = cli_mod,
    });
    b.installArtifact(cli_lib);

    // Cmd
    const cmd_mod = b.createModule(.{
        .root_source_file = b.path("src/cmd.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("cmd", cmd_mod);
    cli_mod.addImport("cmd", cmd_mod);
    const cmd_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cmd",
        .root_module = cmd_mod,
    });
    b.installArtifact(cmd_lib);

    // Arg
    const arg_mod = b.createModule(.{
        .root_source_file = b.path("src/arg.zig"),
        .target = target,
        .optimize = optimize,
    });
    cmd_mod.addImport("arg", arg_mod);
    cli_mod.addImport("arg", arg_mod);
    exe_mod.addImport("arg", arg_mod);
    const arg_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "arg",
        .root_module = arg_mod,
    });
    b.installArtifact(arg_lib);

    // Compress
    const compress_mod = b.createModule(.{
        .root_source_file = b.path("src/compress.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("compress", compress_mod);
    // Create a static library
    const compress_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "compress",
        .root_module = compress_mod,
    });
    b.installArtifact(compress_lib);

    // Stb_image
    const stb_mod = b.addModule("stb_image", .{
        .root_source_file = b.path("src/stb_image.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    stb_mod.addIncludePath(b.path("lib"));
    stb_mod.addCSourceFile(.{ .file = b.path("lib/stb_image.c"), .flags = CFlags });
    exe_mod.addImport("stb_image", stb_mod);
    compress_mod.addImport("stb_image", stb_mod);
    const stb_lib = b.addLibrary(.{
        .name = "stb-image",
        .root_module = stb_mod,
        .linkage = linkage,
    });
    stb_lib.installHeadersDirectory(b.path("lib"), "", .{});
    b.installArtifact(stb_lib);

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
