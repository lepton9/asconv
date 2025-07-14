const std = @import("std");
const stb = @import("stb_image");

pub const Image = struct {
    height: u32,
    widht: u32,
    pixels: [][]u32,
    raw_image: *stb.ImageRaw = undefined,

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
        return img;
    }

    pub fn deinit(self: *Image, allocator: *std.mem.Allocator) void {
        for (self.pixels) |row| {
            allocator.free(row);
        }
        allocator.free(self.pixels);
        self.raw_image.deinit();
        allocator.destroy(self.raw_image);
        allocator.destroy(self);
    }
};

pub fn intensity(pixel: u32) u8 {
    return @truncate((0xFF000000 & pixel) >> 8 * 3);
}

pub fn r(pixel: u32) u8 {
    return @truncate((0x00FF0000 & pixel) >> 8 * 2);
}

pub fn g(pixel: u32) u8 {
    return @truncate((0x0000FF00 & pixel) >> 8 * 1);
}

pub fn b(pixel: u32) u8 {
    return @truncate((0x000000FF & pixel) >> 8 * 0);
}

pub fn pixel_to_char(pixel: u32) u8 {
    const n: u16 = 10;
    const table = " .,:;ox%#@";
    const index = (intensity(pixel) * n) / 255;
    return table[index];
}

pub fn pack_pixel(r_v: u8, g_v: u8, b_v: u8, a_v: u8) u32 {
    // 0xRRGGBBAA
    return (@as(u32, r_v) << 24) |
        (@as(u32, g_v) << 16) |
        (@as(u32, b_v) << 8) |
        @as(u32, a_v);
}

pub fn convert_to_pixel_matrix(allocator: *std.mem.Allocator, image: *stb.ImageRaw) ![][]u32 {
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
            g_v = if (image.nchan > 1) image.data.?[base + 1] else r_v;
            b_v = if (image.nchan > 2) image.data.?[base + 2] else r_v;
            a_v = if (image.nchan > 3) image.data.?[base + 3] else 0xFF;
            pixel.* = pack_pixel(r_v, g_v, b_v, a_v);
        }
    }
    return pixels;
}

// pub fn comp_chunk(mat: [][]u32, h: u32, w: u32) u32 {
//     return 0;
// }
