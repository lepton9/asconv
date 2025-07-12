const std = @import("std");

pub const image = struct {
    height: u32,
    widht: u32,
    pixels: [][]u32,

    pub fn init(allocator: *std.mem.Allocator, height: u32, width: u32) !*image {
        var img = try allocator.create(image);
        img.height = height;
        img.widht = width;
        img.pixels = try allocator.alloc([]u32, height);
        for (img.pixels) |*row| {
            row.* = try allocator.alloc(u32, width);
        }
        return img;
    }

    pub fn deinit(self: *image, allocator: *std.mem.Allocator) void {
        for (self.pixels) |row| {
            allocator.free(row);
        }
        allocator.free(self.pixels);
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
    const n = 10;
    const table = " .,:;ox%#@";
    const index = intensity(pixel) * n / 255;
    return table[index];
}

// pub fn comp_chunk(mat: [][]u32, h: u32, w: u32) u32 {
//     return 0;
// }
