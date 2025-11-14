const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const CFlags = &[_][]const u8{"-fPIC"};
    const options = b.addOptions();

    options.addOption([]const u8, "PROGRAM_NAME", @tagName(zon.name));

    const enable_video = b.option(
        bool,
        "video",
        "Enables video support and requires Ffmpeg libraries",
    ) orelse false;
    options.addOption(bool, "video", enable_video);

    const ffmpeg_dir = b.option(
        []const u8,
        "ffmpeg",
        "Set path to ffmpeg libraries",
    );
    options.addOption(?[]const u8, "ffmpeg", ffmpeg_dir);

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
    exec_mod.addOptions("build_options", options);

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

    // Core
    const core_mod = b.addModule("core", .{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("core", core_mod);

    // Image
    const img_mod = b.createModule(.{
        .root_source_file = b.path("src/img.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("img", img_mod);
    img_mod.addImport("core", core_mod);

    // Video
    const video_mod = b.addModule("video", .{
        .root_source_file = b.path("src/video.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("video", video_mod);
    video_mod.addImport("core", core_mod);

    const term_mod = b.addModule("term", .{
        .root_source_file = b.path("src/term.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_mod.addImport("term", term_mod);
    video_mod.addImport("term", term_mod);
    exec_mod.addImport("term", term_mod);

    // Input
    const input_mod = b.createModule(.{
        .root_source_file = b.path("src/input.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_mod.addImport("input", input_mod);
    video_mod.addImport("input", input_mod);

    // Result
    const result_mod = b.createModule(.{
        .root_source_file = b.path("src/result.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("result", result_mod);
    exec_mod.addImport("result", result_mod);

    // Utils
    const utils_mod = b.createModule(.{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_mod.addImport("utils", utils_mod);
    exe_mod.addImport("utils", utils_mod);
    exec_mod.addImport("utils", utils_mod);

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

    // Ffmpeg
    const av_mod = b.addModule("av", .{
        .root_source_file = b.path("src/av.zig"),
        .target = target,
        .optimize = optimize,
    });
    video_mod.addImport("av", av_mod);
    if (enable_video) {
        linkFfmpeg(b, target, av_mod, ffmpeg_dir);
    }

    // Toml
    const toml = b.dependency("toml", .{ .target = target, .optimize = optimize });
    const toml_mod = toml.module("toml");
    config_mod.addImport("toml", toml_mod);

    // Zcli
    const zcli = b.dependency("zcli", .{ .target = target, .optimize = optimize });
    const zcli_mod = zcli.module("zcli");
    @import("zcli").addVersionInfo(b, zcli_mod, zon.version);
    exe_mod.addImport("zcli", zcli_mod);
    exec_mod.addImport("zcli", zcli_mod);
    usage_mod.addImport("zcli", zcli_mod);

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
    tests.root_module.addImport("exec", exec_mod);
    tests.root_module.addImport("zcli", zcli_mod);
    const run_test_cmd = b.addRunArtifact(tests);
    run_test_cmd.step.dependOn(b.getInstallStep());

    run_test_cmd.addPathDir(b.lib_dir);
    run_cmd.addPathDir(b.lib_dir);

    // Allows to add params to program when building: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test_cmd.step);
}

fn linkFfmpeg(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    lib: *std.Build.Module,
    ffmpeg_dir: ?[]const u8,
) void {
    switch (target.result.os.tag) {
        .windows => {
            const ffmpeg_root_maybe: ?[]const u8 = blk: {
                if (ffmpeg_dir) |ffmpeg_d| {
                    break :blk std.fmt.allocPrint(b.allocator, "{s}", .{ffmpeg_d}) catch return;
                } else {
                    const base_dir = "C:/ProgramData/chocolatey/lib/ffmpeg-shared/tools";
                    var dir = std.fs.openDirAbsolute(base_dir, .{ .iterate = true }) catch |err| {
                        std.debug.print("Couldn't open ffmpeg base dir {s}: {}\n", .{ base_dir, err });
                        return;
                    };
                    defer dir.close();

                    var found_dir: ?[]const u8 = null;
                    var it = dir.iterate();
                    while (it.next() catch null) |entry| {
                        if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, "ffmpeg")) {
                            found_dir = entry.name;
                            break;
                        }
                    }
                    if (found_dir) |d|
                        break :blk std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ base_dir, d }) catch return;
                    break :blk null;
                }
            };

            if (ffmpeg_root_maybe) |ffmpeg_root| {
                defer b.allocator.free(ffmpeg_root);

                const ffmpeg_lib_dir = std.fs.path.join(b.allocator, &.{ ffmpeg_root, "lib" }) catch return;
                const ffmpeg_include_dir = std.fs.path.join(b.allocator, &.{ ffmpeg_root, "include" }) catch return;
                const ffmpeg_bin_dir = std.fs.path.join(b.allocator, &.{ ffmpeg_root, "bin" }) catch return;
                defer b.allocator.free(ffmpeg_lib_dir);
                defer b.allocator.free(ffmpeg_include_dir);
                defer b.allocator.free(ffmpeg_bin_dir);

                lib.addLibraryPath(.{ .cwd_relative = ffmpeg_lib_dir });
                lib.addIncludePath(.{ .cwd_relative = ffmpeg_include_dir });

                const libs = [_][]const u8{
                    "avcodec",
                    "avformat",
                    "avutil",
                    "swscale",
                    "swresample",
                };

                for (libs) |lib_name| {
                    lib.linkSystemLibrary(lib_name, .{});
                }

                var bin_dir = std.fs.openDirAbsolute(ffmpeg_bin_dir, .{ .iterate = true }) catch |err| {
                    std.debug.print("Couldn't open ffmpeg bin dir {s}: {}\n", .{ ffmpeg_bin_dir, err });
                    return;
                };
                defer bin_dir.close();

                var iter = bin_dir.iterate();
                while (iter.next() catch null) |entry| {
                    if (entry.kind != .file) continue;
                    for (libs) |lib_name| {
                        if (std.mem.startsWith(u8, entry.name, lib_name) and
                            std.mem.endsWith(u8, entry.name, ".dll"))
                        {
                            var dll_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                            const dll_path = std.fmt.bufPrint(
                                &dll_path_buf,
                                "{s}/{s}",
                                .{ ffmpeg_bin_dir, entry.name },
                            ) catch return;
                            b.getInstallStep().dependOn(
                                &b.addInstallBinFile(.{ .cwd_relative = dll_path }, entry.name).step,
                            );
                            b.getInstallStep().dependOn(
                                &b.addInstallFileWithDir(.{ .cwd_relative = dll_path }, .lib, entry.name).step,
                            );
                        }
                    }
                }
            }
        },
        else => {
            lib.linkSystemLibrary("libavformat", .{ .use_pkg_config = .force });
            lib.linkSystemLibrary("libavcodec", .{ .use_pkg_config = .force });
            lib.linkSystemLibrary("libswscale", .{ .use_pkg_config = .force });
            lib.linkSystemLibrary("libavutil", .{ .use_pkg_config = .force });
        },
    }
}
