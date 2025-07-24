const std = @import("std");
const stb = @import("stb_image");

const base_char_table = "@#%xo;:,. ";

pub const AsciiCharInfo = struct { start: usize, len: u8 };

pub const AsciiInfo = struct {
    char_table: []const u8,
    char_info: []AsciiCharInfo,
    len: u32,

    pub fn init(allocator: *std.mem.Allocator, ascii_chars: []const u8) !*AsciiInfo {
        var info = try allocator.create(AsciiInfo);
        info.char_table = ascii_chars;
        var char_info = std.ArrayList(AsciiCharInfo).init(allocator.*);
        defer char_info.deinit();

        var i: usize = 0;
        while (i < ascii_chars.len) {
            const len = try std.unicode.utf8ByteSequenceLength(ascii_chars[i]);
            try char_info.append(.{ .start = i, .len = @intCast(len) });
            i += len;
        }

        info.len = @intCast(info.char_table.len);
        info.char_info = try char_info.toOwnedSlice();
        return info;
    }

    pub fn deinit(self: *AsciiInfo, allocator: *std.mem.Allocator) void {
        allocator.destroy(self);
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

    pub fn init(allocator: *std.mem.Allocator, height: u32, width: u32) !*Image {
        var img = try allocator.create(Image);
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

    pub fn resize(self: *Image, allocator: *std.mem.Allocator, height: u32, width: u32) !void {
        for (self.pixels) |row| {
            allocator.free(row);
        }
        allocator.free(self.pixels);
        self.pixels = try allocator.alloc([]u32, height);
        for (self.pixels) |*row| {
            row.* = try allocator.alloc(u32, width);
            @memset(row.*, 0);
        }
        self.height = height;
        self.widht = width;
    }

    pub fn deinit(self: *Image, allocator: *std.mem.Allocator) void {
        for (self.pixels) |row| {
            allocator.free(row);
        }
        allocator.free(self.pixels);
        self.raw_image.deinit();
        allocator.destroy(self.raw_image);
        if (self.ascii_info) |info| {
            info.deinit(allocator);
        }
        allocator.destroy(self);
    }

    pub fn fit_image(self: *Image) void {
        const chunk_h: u32 = @as(u32, @intCast(self.raw_image.height)) / self.height;
        const chunk_w: u32 = @as(u32, @intCast(self.raw_image.width)) / self.widht;
        if (self.raw_image.data == null) return;
        const pixels = convert_to_pixel_matrix(&std.heap.page_allocator, self.raw_image) catch return;
        for (0..self.height) |r_i| {
            for (0..self.widht) |c_i| {
                self.pixels[r_i][c_i] = comp_chunk(pixels, r_i * chunk_h, c_i * chunk_w, chunk_h, chunk_w);
            }
        }
    }

    pub fn pixel_char(self: *Image, pixel: u32) []const u8 {
        if (self.ascii_info) |info| {
            return info.pixel_to_char(pixel);
        }
        return pixel_to_char(pixel);
    }
};

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

pub fn pack_pixel(r_v: u8, g_v: u8, b_v: u8, a_v: u8) u32 {
    // 0xRRGGBBAA
    return (@as(u32, r_v) << 24) |
        (@as(u32, g_v) << 16) |
        (@as(u32, b_v) << 8) |
        @as(u32, a_v);
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
            pixel.* = pack_pixel(r_v, g_v, b_v, a_v);
        }
    }
    return pixels;
}

pub fn calc_chunk_size(h: u32, w: u32, h_new: u32, w_new: u32) struct { u32, u32 } {
    return .{ h / h_new, w / w_new };
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
