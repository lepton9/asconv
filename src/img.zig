const std = @import("std");
const stb = @import("stb_image");
const utils = @import("utils");
const itof = utils.itof;
const ftoi = utils.ftoi;

pub const ImageRaw = stb.ImageRaw;

const gaussian_sigma: f32 = 1.0;
const base_char_table = "@#%xo;:,. ";

pub const AsciiCharInfo = struct { start: usize, len: u8 };

pub const AsciiInfo = struct {
    char_table: []const u8,
    char_info: []AsciiCharInfo,
    len: u32,

    pub fn init(allocator: std.mem.Allocator, ascii_chars: []const u8) !*AsciiInfo {
        var info = try allocator.create(AsciiInfo);
        try info.set_charset(allocator, ascii_chars);
        return info;
    }

    pub fn deinit(self: *AsciiInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.char_info);
        allocator.destroy(self);
    }

    pub fn set_charset(self: *AsciiInfo, allocator: std.mem.Allocator, ascii_chars: []const u8) !void {
        self.char_table = ascii_chars;
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

    pub fn select_char(self: *AsciiInfo, index: usize) []const u8 {
        const char_info: AsciiCharInfo = self.char_info[@min(index, self.char_info.len - 1)];
        return self.char_table[char_info.start .. char_info.start + char_info.len];
    }
};

pub const Core = struct {
    ascii_info: *AsciiInfo,
    edge_chars: []const u8,
    brightness: f32,
    scale: f32,
    edge_detection: bool,

    pub fn init(allocator: std.mem.Allocator) !*Core {
        const core = try allocator.create(Core);
        core.* = .{
            .brightness = 1.0,
            .scale = 1.0,
            .edge_detection = false,
            .edge_chars = "-/|\\",
            // .edge_chars = "|/-\\",
            .ascii_info = try AsciiInfo.init(allocator, base_char_table),
        };
        return core;
    }

    pub fn deinit(self: *Core, allocator: std.mem.Allocator) void {
        self.ascii_info.deinit(allocator);
    }

    fn set_ascii_info(self: *Core, allocator: std.mem.Allocator, charset: []const u8) !void {
        allocator.free(self.ascii_info.char_info);
        try self.ascii_info.set_charset(allocator, charset);
    }
};

const Edge = struct {
    gray: u8,
    mag: f32,
    theta: f32,
};

pub const Image = struct {
    name: []const u8,
    height: u32,
    width: u32,
    pixels: [][]u32,
    raw_image: *ImageRaw = undefined,
    edges: ?[]Edge = null,
    core: *Core = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, height: u32, width: u32) !*Image {
        var img = try allocator.create(Image);
        img.allocator = allocator;
        img.height = height;
        img.width = width;
        img.edges = null;
        img.pixels = try allocator.alloc([]u32, height);
        for (img.pixels) |*row| {
            row.* = try allocator.alloc(u32, width);
            @memset(row.*, 0);
        }
        img.raw_image = try allocator.create(ImageRaw);
        img.raw_image.* = ImageRaw{};
        return img;
    }

    pub fn deinit(self: *Image) void {
        if (self.edges) |edges| {
            self.allocator.free(edges);
        }
        for (self.pixels) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.pixels);
        self.raw_image.deinit();
        self.core.deinit(self.allocator);
        self.allocator.destroy(self.core);
        self.allocator.destroy(self.raw_image);
        self.allocator.destroy(self);
    }

    pub fn resize(self: *Image, height: u32, width: u32) !void {
        for (self.pixels) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.pixels);
        self.pixels = try self.allocator.alloc([]u32, height);
        for (self.pixels) |*row| {
            row.* = try self.allocator.alloc(u32, width);
            @memset(row.*, 0);
        }
        if (self.edges) |*edges| {
            edges = try self.allocator.realloc(edges, Edge, width * height);
        }
        self.height = height;
        self.width = width;
    }

    pub fn set_raw_image(self: *Image, raw_image: ImageRaw, filename: []const u8) void {
        if (!self.raw_image.empty()) {
            self.raw_image.deinit();
        }
        self.raw_image.* = raw_image;
        self.name = filename;
    }

    pub fn set_edge_detection(self: *Image) !void {
        self.core.edge_detection = true;
        self.edges = try self.allocator.alloc(Edge, self.width * self.height);
    }

    pub fn set_ascii_info(self: *Image, charset: []const u8) !void {
        try self.core.set_ascii_info(self.allocator, charset);
    }

    pub fn fit_image(self: *Image) !void {
        if (self.raw_image.data == null) return error.NoImageData;
        const pixels: [][]u32 = try convert_to_pixel_matrix(self.allocator, self.raw_image);
        defer free_pixel_mat(pixels, self.allocator);
        scale_nearest(
            pixels,
            self.pixels,
            @intCast(self.raw_image.width),
            @intCast(self.raw_image.height),
            self.width,
            self.height,
        );
        if (self.core.edge_detection) {
            try calc_edges(self.allocator, self.edges.?, self.pixels, self.width, self.height);
        }
    }

    fn pixel_to_char(self: *Image, pixel: u32) []const u8 {
        const avg: usize = pixel_avg(pixel);
        const brightness: usize = std.math.clamp(
            utils.ftoi(usize, (utils.itof(f32, avg) * self.core.brightness)),
            0,
            255,
        );
        if (brightness == 0) return " ";
        const index = (brightness * self.core.ascii_info.len) / 256;
        return self.core.ascii_info.select_char(index);
    }

    fn get_char(self: *Image, x: usize, y: usize) []const u8 {
        if (self.core.edge_detection) {
            if (edge_char(self.edges.?[y * self.width + x], self.core.edge_chars)) |c| {
                return c;
            }
        }
        return self.pixel_to_char(self.pixels[y][x]);
    }

    pub fn to_ascii(self: *Image) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const c: []const u8 = self.get_char(x, y);
                try buffer.appendSlice(c);
                try buffer.appendSlice(c);
            }
            try buffer.appendSlice("\n");
        }
        return buffer.toOwnedSlice();
    }
};

fn scale_nearest(
    src: [][]u32,
    dst: [][]u32,
    src_width: usize,
    src_height: usize,
    dst_width: usize,
    dst_height: usize,
) void {
    for (dst, 0..) |*dst_row, y| {
        for (dst_row.*, 0..) |*dst_pixel, x| {
            const src_x = @min(src_width - 1, (x * src_width) / dst_width);
            const src_y = @min(src_height - 1, (y * src_height) / dst_height);
            dst_pixel.* = src[src_y][src_x];
        }
    }
}

fn scale_bilinear(
    src: [][]u32,
    dst: [][]u32,
    src_width: usize,
    src_height: usize,
    dst_width: usize,
    dst_height: usize,
) void {
    for (dst, 0..) |*dst_row, y| {
        const fy: f64 = (itof(f64, y) * itof(f64, src_height)) / itof(f64, dst_height);
        const y0: usize = @min(src_height - 1, ftoi(usize, fy));
        const y1: usize = @min(src_height - 1, y0 + 1);
        const wy: f64 = fy - itof(f64, y0);

        for (dst_row.*, 0..) |*dst_pixel, x| {
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
            dst_pixel.* = pack_rgba(result);
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

fn unpack_rgba(pixel: u32) [4]u8 {
    return .{
        @intCast((pixel >> 24) & 0xFF),
        @intCast((pixel >> 16) & 0xFF),
        @intCast((pixel >> 8) & 0xFF),
        @intCast(pixel & 0xFF),
    };
}

fn pack_rgba(rgba: [4]u8) u32 {
    return (@as(u32, rgba[0]) << 24) |
        (@as(u32, rgba[1]) << 16) |
        (@as(u32, rgba[2]) << 8) |
        @as(u32, rgba[3]);
}

pub fn convert_to_pixel_matrix(allocator: std.mem.Allocator, image: *ImageRaw) ![][]u32 {
    const w: usize = @intCast(image.width);
    const h: usize = @intCast(image.height);
    const channels: usize = @intCast(image.nchan);
    const pixels = try allocator.alloc([]u32, h);
    var r_v: u8, var g_v: u8, var b_v: u8, var a_v: u8 = .{ 0, 0, 0, 0 };

    for (pixels, 0..) |*row, y| {
        row.* = try allocator.alloc(u32, w);
        for (row.*, 0..) |*pixel, x| {
            const base = (y * w + x) * channels;
            r_v = image.data.?[base];
            g_v = if (channels > 1) image.data.?[base + 1] else r_v;
            b_v = if (channels > 2) image.data.?[base + 2] else r_v;
            a_v = if (channels > 3) image.data.?[base + 3] else 0xFF;
            pixel.* = pack_rgba(.{ r_v, g_v, b_v, a_v });
        }
    }
    return pixels;
}

pub fn free_pixel_mat(pixels: [][]u32, allocator: std.mem.Allocator) void {
    for (pixels) |row| allocator.free(row);
    allocator.free(pixels);
}

pub fn comp_chunk(mat: [][]u32, row: u64, col: u64, h: u64, w: u64) u32 {
    if (h == 0 or w == 0) return 0;
    var sum: u64 = 0;
    const max_height: u64 = @as(u64, @intCast(mat.len)) - row;
    const max_width: u64 = @as(u64, @intCast(mat[0].len)) - col;
    const iter_height = if (h < max_height) h else max_height;
    const iter_width = if (w < max_width) w else max_width;
    for (0..iter_height) |i| {
        for (0..iter_width) |j| {
            sum += mat[row + i][col + j];
        }
    }
    return @intCast(sum / (h * w));
}

fn gray_scale_image(
    allocator: std.mem.Allocator,
    pixels: [][]u32,
    width: usize,
    height: usize,
) ![]u8 {
    var gray = try allocator.alloc(u8, width * height);
    for (1..height) |y| {
        for (1..width) |x| {
            gray[y * width + x] = gray_scale_avg(pixels[y][x]);
        }
    }
    return gray;
}

fn edge_char(edge: Edge, edge_chars: []const u8) ?[]const u8 {
    const threshold: f32 = 50;
    if (edge.mag < threshold) {
        return null;
    }
    const deg = std.math.radiansToDegrees(edge.theta);
    const ind: usize = blk: {
        if (deg < 22.5 or deg >= 157.5) break :blk 0;
        if (deg < 67.5) break :blk 1;
        if (deg < 112.5) break :blk 2;
        break :blk 3;
    };
    return edge_chars[ind .. ind + 1];
}

fn calc_edges(
    allocator: std.mem.Allocator,
    edges: []Edge,
    pixels: [][]u32,
    width: usize,
    height: usize,
) !void {
    const gray = try gray_scale_image(allocator, pixels, width, height);
    defer allocator.free(gray);
    return sobel_op(edges, gray, width, height);
}

fn sobel_op(
    edges: []Edge,
    img: []u8,
    width: usize,
    height: usize,
) !void {
    @memset(edges, Edge{ .gray = 0, .theta = 0, .mag = 0 });

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

            edges[y * width + x] = Edge{
                .gray = img[y * width + x],
                .mag = std.math.sqrt(gx * gx + gy * gy),
                .theta = blk: {
                    var t = std.math.atan2(-gy, gx) + std.math.pi / 2.0;
                    if (t < 0) t += std.math.pi;
                    break :blk @mod(t, std.math.pi);
                },
            };
        }
    }
}

fn gaussian_kernel(
    comptime sigma: f32,
) []f32 {
    const size: i32 = @intFromFloat(sigma * 6);
    const kernel_size = if (size % 2 == 0) size + 1 else size;
    var kernel: [kernel_size * kernel_size]f32 = undefined;
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
    return &kernel;
}

fn gaussian_smoothing(
    img: []u8,
    output: []u8,
    width: usize,
    height: usize,
) void {
    const kernel = gaussian_kernel(gaussian_sigma);
    const kernel_size: usize = @intCast(std.math.sqrt(kernel.len));
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

pub fn load_image(filename: []const u8, nchannels: ?i32) !ImageRaw {
    return try stb.load_image(filename, nchannels);
}

pub fn load_image_from_memory(filename: []const u8) !ImageRaw {
    return try stb.load_image_from_memory(filename);
}
