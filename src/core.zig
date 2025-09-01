const std = @import("std");
pub const time = @import("time.zig");
const utils = @import("utils");
const itof = utils.itof;
const ftoi = utils.ftoi;

const base_gaussian_sigma: f32 = 1.0;
const base_char_table = " .,:;ox%#@";

pub const ColorMode = enum {
    truecolor,
    color256,
};

pub const EdgeDetectionAlg = enum {
    Sobel,
    LoG, // Laplacian of Gaussian
    DoG, // Difference of Gaussian
};

pub const AsciiCharInfo = struct { start: usize, len: u8 };

pub const AsciiInfo = struct {
    char_table: []const u8,
    char_info: []AsciiCharInfo,
    len: u32,

    pub fn init(allocator: std.mem.Allocator, ascii_chars: []const u8) !*AsciiInfo {
        var info = try allocator.create(AsciiInfo);
        try info.init_charset(allocator, ascii_chars);
        return info;
    }

    pub fn deinit(self: *AsciiInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.char_table);
        allocator.free(self.char_info);
        allocator.destroy(self);
    }

    pub fn init_charset(
        self: *AsciiInfo,
        allocator: std.mem.Allocator,
        ascii_chars: []const u8,
    ) !void {
        self.char_table = try allocator.dupe(u8, ascii_chars);
        var char_info = std.ArrayList(AsciiCharInfo).init(allocator);
        defer char_info.deinit();
        var i: usize = 0;
        while (i < ascii_chars.len) {
            const len = try std.unicode.utf8ByteSequenceLength(ascii_chars[i]);
            try char_info.append(.{ .start = i, .len = @intCast(len) });
            i += len;
        }
        self.len = @intCast(self.char_table.len);
        self.char_info = try char_info.toOwnedSlice();
    }

    pub fn set_charset(
        self: *AsciiInfo,
        allocator: std.mem.Allocator,
        ascii_chars: []const u8,
    ) !void {
        allocator.free(self.char_table);
        allocator.free(self.char_info);
        try self.init_charset(allocator, ascii_chars);
    }

    pub fn select_char(self: *AsciiInfo, index: usize) []const u8 {
        const char_info: AsciiCharInfo = self.char_info[@min(index, self.char_info.len - 1)];
        return self.char_table[char_info.start .. char_info.start + char_info.len];
    }

    pub fn reverse(self: *AsciiInfo, allocator: std.mem.Allocator) !void {
        var reversed = std.ArrayList(u8).init(allocator);
        defer reversed.deinit();
        var i = self.char_info.len;
        while (i > 0) {
            i -= 1;
            const info = self.char_info[i];
            try reversed.appendSlice(self.char_table[info.start .. info.start + info.len]);
        }
        try self.set_charset(allocator, reversed.items);
    }
};

pub const EdgeData = struct {
    img: []u8,
    mag: []f32,
    theta: []f32,

    pub fn init(allocator: std.mem.Allocator, height: u32, width: u32) !EdgeData {
        const edges: EdgeData = .{
            .img = try allocator.alloc(u8, width * height),
            .mag = try allocator.alloc(f32, width * height),
            .theta = try allocator.alloc(f32, width * height),
        };
        return edges;
    }

    pub fn deinit(self: EdgeData, allocator: std.mem.Allocator) void {
        allocator.free(self.img);
        allocator.free(self.mag);
        allocator.free(self.theta);
    }

    pub fn resize(self: EdgeData, allocator: std.mem.Allocator, height: u32, width: u32) !void {
        self.img = try allocator.realloc(self.img, u8, width * height);
        self.mag = try allocator.realloc(self.mag, f32, width * height);
        self.theta = try allocator.realloc(self.theta, f32, width * height);
    }

    pub fn reset(self: EdgeData) void {
        @memset(self.img, 0);
        @memset(self.mag, 0);
        @memset(self.theta, 0);
    }
};

pub const Core = struct {
    ascii_info: *AsciiInfo,
    edge_chars: []const u8,
    brightness: f32,
    scale: f32,
    color: bool,
    color_mode: ColorMode,
    edge_detection: bool,
    edge_alg: EdgeDetectionAlg,
    sigma1: f32,
    sigma2: f32,
    perf: time.Time,

    pub fn init(allocator: std.mem.Allocator) !*Core {
        const core = try allocator.create(Core);
        core.* = .{
            .brightness = 1.0,
            .scale = 1.0,
            .color = false,
            .color_mode = .color256,
            .edge_detection = false,
            .edge_alg = .Sobel,
            .edge_chars = "-/|\\",
            .sigma1 = base_gaussian_sigma,
            .sigma2 = base_gaussian_sigma / 1.6,
            .ascii_info = try AsciiInfo.init(allocator, base_char_table),
            .perf = time.Time.init(),
        };
        return core;
    }

    pub fn deinit(self: *Core, allocator: std.mem.Allocator) void {
        self.ascii_info.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn set_ascii_info(self: *Core, allocator: std.mem.Allocator, charset: []const u8) !void {
        try self.ascii_info.set_charset(allocator, charset);
    }

    pub fn set_sigma(self: *Core, sigma: f32) void {
        self.sigma1 = sigma;
        self.sigma2 = sigma / 1.6;
    }

    pub fn set_edge_alg(self: *Core, alg: []const u8) !void {
        self.edge_alg = utils.string_to_enum_ic(EdgeDetectionAlg, alg) orelse
            return error.NoAlgorithmFound;
    }

    pub fn set_color_mode(self: *Core, mode: []const u8) !void {
        self.color_mode = utils.string_to_enum_ic(ColorMode, mode) orelse
            return error.NoColorModeFound;
    }

    pub fn toggle_color(self: *Core) void {
        self.color = !self.color;
    }

    pub fn pixel_to_char(core: *Core, pixel: u32) []const u8 {
        const avg: usize = pixel_avg(pixel);
        const brightness: usize = std.math.clamp(
            utils.ftoi(usize, (utils.itof(f32, avg) * core.brightness)),
            0,
            255,
        );
        if (brightness == 0) return " ";
        const index = (brightness * core.ascii_info.len) / 256;
        return core.ascii_info.select_char(index);
    }
};

pub fn scale_nearest(
    src: []u32,
    dst: []u32,
    src_width: usize,
    src_height: usize,
    dst_width: usize,
    dst_height: usize,
) void {
    for (0..dst_height) |y| {
        for (0..dst_width) |x| {
            const src_x = @min(src_width - 1, (x * src_width) / dst_width);
            const src_y = @min(src_height - 1, (y * src_height) / dst_height);
            dst[y * dst_width + x] = src[src_y * src_width + src_x];
        }
    }
}

pub fn scale_bilinear(
    src: []u32,
    dst: []u32,
    src_width: usize,
    src_height: usize,
    dst_width: usize,
    dst_height: usize,
) void {
    for (0..dst_height) |y| {
        const fy: f64 = (itof(f64, y) * itof(f64, src_height)) / itof(f64, dst_height);
        const y0: usize = @min(src_height - 1, ftoi(usize, fy));
        const y1: usize = @min(src_height - 1, y0 + 1);
        const wy: f64 = fy - itof(f64, y0);

        for (0..dst_width) |x| {
            const fx: f64 = (itof(f64, x) * itof(f64, src_width)) / itof(f64, dst_width);
            const x0: usize = @min(src_width - 1, ftoi(usize, fx));
            const x1: usize = @min(src_width - 1, x0 + 1);
            const wx: f64 = fx - itof(f64, x0);

            const p00 = unpack_rgba(src[y0][x0]);
            const p10 = unpack_rgba(src[y0][x1]);
            const p01 = unpack_rgba(src[y1][x0]);
            const p11 = unpack_rgba(src[y1][x1]);

            var result: [4]u8 = undefined;

            inline for (0..4) |i| {
                const top: f64 = (1.0 - wx) * itof(f64, p00[i]) + wx * itof(f64, p10[i]);
                const bot: f64 = (1.0 - wx) * itof(f64, p01[i]) + wx * itof(f64, p11[i]);
                const value: f64 = (1.0 - wy) * top + wy * bot;
                result[i] = @intFromFloat(std.math.clamp(value, 0.0, 255.0));
            }
            dst[y * dst_width + x] = pack_rgba(result);
        }
    }
}

pub fn r(pixel: u32) u8 {
    return @truncate((0xFF000000 & pixel) >> 8 * 3);
}

pub fn g(pixel: u32) u8 {
    return @truncate((0x00FF0000 & pixel) >> 8 * 2);
}

pub fn b(pixel: u32) u8 {
    return @truncate((0x0000FF00 & pixel) >> 8 * 1);
}

pub fn a(pixel: u32) u8 {
    return @truncate((0x000000FF & pixel) >> 8 * 0);
}

pub fn pixel_avg(pixel: u32) u8 {
    const r_value = r(pixel);
    const g_value = g(pixel);
    const b_value = b(pixel);
    return @truncate((@as(u16, r_value) + @as(u16, g_value) + @as(u16, b_value)) / 3);
}

pub fn gray_scale(pixel: u32) u32 {
    const r_val: f32 = @floatFromInt(r(pixel));
    const g_val: f32 = @floatFromInt(g(pixel));
    const b_val: f32 = @floatFromInt(b(pixel));
    return pack_rgba(.{
        @intFromFloat(r_val * 0.21),
        @intFromFloat(g_val * 0.72),
        @intFromFloat(b_val * 0.07),
        a(pixel),
    });
}

pub fn gray_scale_avg(pixel: u32) u8 {
    const r_val: f32 = @floatFromInt(r(pixel));
    const g_val: f32 = @floatFromInt(g(pixel));
    const b_val: f32 = @floatFromInt(b(pixel));
    const val: f32 = 0.21 * r_val + 0.72 * g_val + 0.07 * b_val;
    return @intFromFloat(val);
}

pub fn unpack_rgba(pixel: u32) [4]u8 {
    return .{
        @intCast((pixel >> 24) & 0xFF),
        @intCast((pixel >> 16) & 0xFF),
        @intCast((pixel >> 8) & 0xFF),
        @intCast(pixel & 0xFF),
    };
}

pub fn pack_rgba(rgba: [4]u8) u32 {
    return (@as(u32, rgba[0]) << 24) |
        (@as(u32, rgba[1]) << 16) |
        (@as(u32, rgba[2]) << 8) |
        @as(u32, rgba[3]);
}

pub fn gray_scale_filter(
    pixels: []u32,
    output: []u8,
    width: usize,
    height: usize,
) void {
    for (1..height) |y| {
        for (1..width) |x| {
            output[y * width + x] = gray_scale_avg(pixels[y * width + x]);
        }
    }
}

pub fn edge_char(edges: EdgeData, i: usize, edge_chars: []const u8) ?[]const u8 {
    const threshold: f32 = 50;
    if (edges.mag[i] < threshold) {
        return null;
    }
    const deg = std.math.radiansToDegrees(edges.theta[i]);
    const ind: usize = blk: {
        if (deg < 22.5 or deg >= 157.5) break :blk 0;
        if (deg < 67.5) break :blk 1;
        if (deg < 112.5) break :blk 2;
        break :blk 3;
    };
    return edge_chars[ind .. ind + 1];
}

pub fn calc_edges(
    allocator: std.mem.Allocator,
    core: Core,
    edges: EdgeData,
    pixels: []u32,
    width: usize,
    height: usize,
) !void {
    edges.reset();
    gray_scale_filter(pixels, edges.img, width, height);
    switch (core.edge_alg) {
        .Sobel => {
            return sobel_filter(edges, edges.img, width, height, true);
        },
        .LoG => {
            return try laplacian_of_gaussian(allocator, core, edges, edges.img, width, height);
        },
        .DoG => {
            try difference_of_gaussians(allocator, core, edges, edges.img, width, height);
            return sobel_filter(edges, edges.img, width, height, true);
        },
    }
}

pub fn sobel_filter(
    edges: EdgeData,
    img: []u8,
    width: usize,
    height: usize,
    calc_mag: bool,
) void {
    const Gx = [3][3]i32{ .{ -1, 0, 1 }, .{ -2, 0, 2 }, .{ -1, 0, 1 } };
    const Gy = [3][3]i32{ .{ -1, -2, -1 }, .{ 0, 0, 0 }, .{ 1, 2, 1 } };

    for (1..height - 1) |y| {
        for (1..width - 1) |x| {
            var gx: f32 = 0;
            var gy: f32 = 0;

            inline for (0..3) |i| {
                inline for (0..3) |j| {
                    const px = utils.itof(f32, img[(y + i - 1) * width + (x + j - 1)]);
                    gx += @as(f32, @floatFromInt(Gx[i][j])) * @as(f32, px);
                    gy += @as(f32, @floatFromInt(Gy[i][j])) * @as(f32, px);
                }
            }

            const ind = y * width + x;
            edges.img[ind] = img[ind];
            if (calc_mag) edges.mag[ind] = std.math.sqrt(gx * gx + gy * gy);
            edges.theta[ind] = blk: {
                var t = std.math.atan2(-gy, gx) + std.math.pi / 2.0;
                if (t < 0) t += std.math.pi;
                break :blk @mod(t, std.math.pi);
            };
        }
    }
}

pub fn laplacian_of_gaussian(
    allocator: std.mem.Allocator,
    core: Core,
    edges: EdgeData,
    img: []u8,
    width: usize,
    height: usize,
) !void {
    const threshold = 10;
    const log_img = try allocator.alloc(f32, width * height);
    defer allocator.free(log_img);
    try gaussian_smoothing(allocator, img, img, width, height, core.sigma1);
    try laplacian_filter(allocator, img, log_img, width, height, core.sigma1);
    zero_crossings(log_img, edges.mag, width, height, threshold);
    sobel_filter(edges, img, width, height, false);
}

pub fn laplacian_filter(
    allocator: std.mem.Allocator,
    img: []u8,
    output: []f32,
    width: usize,
    height: usize,
    sigma: f32,
) !void {
    const kernel_size = get_kernel_size(width, height, sigma);
    const kernel = try laplacian_of_gaussian_kernel(allocator, kernel_size, sigma);
    defer allocator.free(kernel);
    const half: usize = @intCast((kernel_size - 1) / 2);

    for (half..height - half) |y| {
        for (half..width - half) |x| {
            var sum: f32 = 0.0;

            for (0..kernel_size) |ky| {
                for (0..kernel_size) |kx| {
                    const ix: i32 = @as(i32, @intCast(x)) + @as(i32, @intCast(kx)) - @as(i32, @intCast(half));
                    const iy: i32 = @as(i32, @intCast(y)) + @as(i32, @intCast(ky)) - @as(i32, @intCast(half));

                    const pixel: f32 =
                        @floatFromInt(img[@intCast(iy * @as(i32, @intCast(width)) + ix)]);
                    sum += pixel * kernel[ky * kernel_size + kx];
                }
            }

            const ind = y * width + x;
            output[ind] = sum;
        }
    }
}

pub fn laplacian_of_gaussian_kernel(
    allocator: std.mem.Allocator,
    kernel_size: usize,
    sigma: f32,
) ![]f32 {
    var kernel: []f32 = try allocator.alloc(f32, kernel_size * kernel_size);

    const s2 = sigma * sigma;
    const s4 = s2 * s2;
    const center: f32 = @floatFromInt((kernel_size - 1) / 2);
    var sum: f32 = 0.0;

    for (0..kernel_size) |i| {
        for (0..kernel_size) |j| {
            const x: f32 = @as(f32, @floatFromInt(i)) - center;
            const y: f32 = @as(f32, @floatFromInt(j)) - center;
            const r2 = x * x + y * y;

            const LoG_xy = (-1.0 / (std.math.pi * s4)) *
                (1.0 - (r2 / (2.0 * s2))) *
                @exp(-r2 / (2.0 * s2));

            kernel[i * kernel_size + j] = LoG_xy;
            sum += LoG_xy;
        }
    }

    const avg = sum / @as(f32, @floatFromInt(kernel.len));
    for (0..kernel.len) |k| {
        kernel[k] -= avg;
    }
    return kernel;
}

pub fn zero_crossings(
    log_img: []f32,
    output: []f32,
    width: usize,
    height: usize,
    threshold: f32,
) void {
    for (1..height - 1) |y| {
        for (1..width - 1) |x| {
            const idx = y * width + x;
            const val = log_img[idx];
            var is_edge = false;

            inline for ([_]i32{ -1, 0, 1 }) |dy| {
                inline for ([_]i32{ -1, 0, 1 }) |dx| {
                    if (dx == 0 and dy == 0) continue;

                    const nx = @as(i32, @intCast(x)) + dx;
                    const ny = @as(i32, @intCast(y)) + dy;
                    const nidx = @as(usize, @intCast(ny * @as(i32, @intCast(width)) + nx));

                    const nval = log_img[nidx];

                    if ((val > 0 and nval < 0) or (val < 0 and nval > 0)) {
                        if (@abs(val - nval) > threshold) {
                            is_edge = true;
                        }
                    }
                }
            }
            output[idx] = if (is_edge) 255 else 0;
        }
    }
}

pub fn difference_of_gaussians(
    allocator: std.mem.Allocator,
    core: Core,
    edges: EdgeData,
    img: []u8,
    width: usize,
    height: usize,
) !void {
    const smooth1 = try allocator.alloc(u8, width * height);
    const smooth2 = try allocator.alloc(u8, width * height);
    defer allocator.free(smooth1);
    defer allocator.free(smooth2);
    try gaussian_smoothing(allocator, img, smooth1, width, height, core.sigma1);
    try gaussian_smoothing(allocator, img, smooth2, width, height, core.sigma2);

    for (0..width * height) |i| {
        const diff = @as(i16, smooth1[i]) - @as(i16, smooth2[i]);
        edges.img[i] = @as(u8, @intCast(std.math.clamp(diff + 128, 0, 255)));
    }
}

fn gaussian_kernel(
    allocator: std.mem.Allocator,
    kernel_size: usize,
    sigma: f32,
) ![]f32 {
    var kernel: []f32 = try allocator.alloc(f32, kernel_size * kernel_size);
    const center: f32 = @floatFromInt((kernel_size - 1) / 2);
    const s: f32 = 2.0 * sigma * sigma;
    var sum: f32 = 0.0;
    for (0..kernel_size) |i| {
        for (0..kernel_size) |j| {
            const x: f32 = @as(f32, @floatFromInt(i)) - center;
            const y: f32 = @as(f32, @floatFromInt(j)) - center;
            kernel[i * kernel_size + j] = @exp(((x * x + y * y) / s) * (-1)) / (std.math.pi * s);
            sum += kernel[i * kernel_size + j];
        }
    }
    for (0..kernel_size * kernel_size) |i| {
        kernel[i] /= sum;
    }
    return kernel;
}

fn gaussian_smoothing(
    allocator: std.mem.Allocator,
    img: []u8,
    output: []u8,
    width: usize,
    height: usize,
    sigma: f32,
) !void {
    const kernel_size: usize = get_kernel_size(width, height, sigma);
    const kernel = try gaussian_kernel(allocator, kernel_size, sigma);
    defer allocator.free(kernel);
    const center: i32 = @as(i32, @intCast(kernel_size / 2));
    for (0..height) |y| {
        for (0..width) |x| {
            var sum: f32 = 0;
            for (0..kernel_size) |ky| {
                for (0..kernel_size) |kx| {
                    const ix: i32 = @as(i32, @intCast(x)) + @as(i32, @intCast(kx)) - center;
                    const iy: i32 = @as(i32, @intCast(y)) + @as(i32, @intCast(ky)) - center;

                    if (ix >= 0 and iy >= 0 and
                        ix < @as(i32, @intCast(width)) and iy < @as(i32, @intCast(height)))
                    {
                        const pixel: f32 = @as(
                            f32,
                            @floatFromInt(img[@intCast(iy * @as(i32, @intCast(width)) + ix)]),
                        );
                        sum += pixel * kernel[ky * kernel_size + kx];
                    }
                }
            }
            output[y * width + x] = @intFromFloat(std.math.clamp(sum, 0.0, 255.0));
        }
    }
}

fn get_kernel_size(width: usize, height: usize, sigma: f32) usize {
    const min_dim: usize = if (width < height) width else height;
    var size: usize = @as(usize, @intFromFloat(@ceil(6.0 * sigma))) | 1;
    if (size > min_dim / 4) {
        size = (min_dim / 4) | 1;
        if (size < 3) size = 3;
    }
    return size;
}

pub fn rgb_to_ansi256(r_: u8, g_: u8, b_: u8) u8 {
    const r6 = @divTrunc(r_, 51);
    const g6 = @divTrunc(g_, 51);
    const b6 = @divTrunc(b_, 51);
    return 16 + 36 * r6 + 6 * g6 + b6;
}

pub fn append_256_color(buffer: *std.ArrayList(u8), char: []const u8, p: u32) !void {
    var buf: [64]u8 = undefined;
    try buffer.appendSlice(try std.fmt.bufPrint(
        &buf,
        "\x1b[38;5;{d}m{s}{s}\x1b[0m",
        .{ rgb_to_ansi256(r(p), g(p), b(p)), char, char },
    ));
}

pub fn append_truecolor(buffer: *std.ArrayList(u8), char: []const u8, p: u32) !void {
    var buf: [64]u8 = undefined;
    try buffer.appendSlice(try std.fmt.bufPrint(
        &buf,
        "\x1b[38;2;{d};{d};{d}m{s}{s}\x1b[0m",
        .{ r(p), g(p), b(p), char, char },
    ));
}

pub fn get_scale(img_w: u32, img_h: u32, target_w: u32, target_h: u32) f32 {
    const scale_w: f32 = utils.itof(f32, target_w) / utils.itof(f32, img_w);
    const scale_h: f32 = utils.itof(f32, target_h) / utils.itof(f32, img_h);
    return @min(scale_w, scale_h);
}
