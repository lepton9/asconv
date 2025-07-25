const std = @import("std");
const stb = @import("stb_image");
const utils = @import("utils");
const itof = utils.itof;
const ftoi = utils.ftoi;

const base_char_table = "@#%xo;:,. ";

pub const AsciiCharInfo = struct { start: usize, len: u8 };

pub const AsciiInfo = struct {
    char_table: []const u8,
    char_info: []AsciiCharInfo,
    len: u32,

    pub fn init(allocator: *std.mem.Allocator, ascii_chars: []const u8) !*AsciiInfo {
        var info = try allocator.create(AsciiInfo);
        try info.set_charset(ascii_chars);
        return info;
    }

    pub fn deinit(self: *AsciiInfo, allocator: *std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn set_charset(self: *AsciiInfo, ascii_chars: []const u8) !void {
        const malloc = std.heap.page_allocator;
        self.char_table = ascii_chars;
        var char_info = std.ArrayList(AsciiCharInfo).init(malloc);
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

    pub fn select_char(self: *AsciiInfo, index: u32) []const u8 {
        const char_info: AsciiCharInfo = self.char_info[@min(index, self.char_info.len - 1)];
        return self.char_table[char_info.start .. char_info.start + char_info.len];
    }

    pub fn pixel_to_char(self: *AsciiInfo, pixel: u32) []const u8 {
        const index: u32 = (gray_scale(pixel) * self.len) / 255;
        return self.select_char(index);
    }
};

pub const Image = struct {
    name: []const u8,
    height: u32,
    widht: u32,
    pixels: [][]u32,
    raw_image: *stb.ImageRaw = undefined,
    ascii_info: ?*AsciiInfo = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, height: u32, width: u32) !*Image {
        var img = try allocator.create(Image);
        img.allocator = allocator;
        img.height = height;
        img.widht = width;
        img.pixels = try allocator.alloc([]u32, height);
        for (img.pixels) |*row| {
            row.* = try allocator.alloc(u32, width);
            @memset(row.*, 0);
        }
        img.raw_image = try allocator.create(stb.ImageRaw);
        img.raw_image.* = stb.ImageRaw{};
        img.ascii_info = null;
        return img;
    }

    pub fn deinit(self: *Image) void {
        for (self.pixels) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.pixels);
        self.raw_image.deinit();
        self.allocator.destroy(self.raw_image);
        if (self.ascii_info) |info| {
            info.deinit(&self.allocator);
        }
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
        self.height = height;
        self.widht = width;
    }

    pub fn set_raw_image(self: *Image, raw_image: stb.ImageRaw, filename: []const u8) void {
        if (!self.raw_image.empty()) {
            self.raw_image.deinit();
        }
        self.raw_image.* = raw_image;
        self.name = filename;
    }

    pub fn set_ascii_info(self: *Image, charset: []const u8) !void {
        if (self.ascii_info) |info| {
            info.deinit(&self.allocator);
        }
        self.ascii_info = try AsciiInfo.init(&self.allocator, charset);
    }

    fn compress_img(self: *Image) void {
        const chunk_h: u32 = @max(@as(u32, @intCast(self.raw_image.height)) / self.height, 1);
        const chunk_w: u32 = @max(@as(u32, @intCast(self.raw_image.width)) / self.widht, 1);
        const pixels: [][]u32 = convert_to_pixel_matrix(&std.heap.page_allocator, self.raw_image) catch return;
        defer free_pixel_mat(pixels, &std.heap.page_allocator);
        for (0..self.height) |r_i| {
            for (0..self.widht) |c_i| {
                self.pixels[r_i][c_i] = comp_chunk(pixels, r_i * chunk_h, c_i * chunk_w, chunk_h, chunk_w);
            }
        }
    }

    pub fn fit_image(self: *Image) !void {
        if (self.raw_image.data == null) return error.NoImageData;
        const pixels: [][]u32 = try convert_to_pixel_matrix(&std.heap.page_allocator, self.raw_image);
        defer free_pixel_mat(pixels, &std.heap.page_allocator);
        scale_nearest(
            pixels,
            self.pixels,
            @intCast(self.raw_image.width),
            @intCast(self.raw_image.height),
            self.widht,
            self.height,
        );
    }

    fn pixel_char(self: *Image, pixel: u32) []const u8 {
        if (self.ascii_info) |info| {
            return info.pixel_to_char(pixel);
        }
        return pixel_to_char(pixel);
    }

    pub fn to_ascii(self: *Image) ![]const u8 {
        var buffer = std.ArrayList(u8).init(std.heap.page_allocator);
        defer buffer.deinit();
        for (self.pixels) |row| {
            for (row) |pixel| {
                const c: []const u8 = self.pixel_char(pixel);
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

pub fn gray_scale(pixel: u32) u8 {
    const r_val: f32 = @floatFromInt(r(pixel));
    const g_val: f32 = @floatFromInt(g(pixel));
    const b_val: f32 = @floatFromInt(b(pixel));
    const val: f32 = 0.21 * r_val + 0.72 * g_val + 0.07 * b_val;
    return @intFromFloat(val);
}

pub fn pixel_to_char(pixel: u32) []const u8 {
    const n: u32 = base_char_table.len;
    const index = (gray_scale(pixel) * n) / 255;
    return base_char_table[index .. index + 1];
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

pub fn convert_to_pixel_matrix(allocator: *const std.mem.Allocator, image: *stb.ImageRaw) ![][]u32 {
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

pub fn free_pixel_mat(pixels: [][]u32, allocator: *const std.mem.Allocator) void {
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
