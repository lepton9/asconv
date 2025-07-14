const std = @import("std");
const stb = @import("stb_image");
const compress = @import("compress");
const Image = compress.Image;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filename = "./images/test.jpg";
    const height: u32 = 10;
    const width: u32 = 10;

    var malloc = gpa.allocator();
    const img = try Image.init(&malloc, height, width);
    defer Image.deinit(img, &malloc);
    for (img.pixels) |row| {
        for (row) |pixel| {
            try stdout.print("{c} ", .{compress.pixel_to_char(pixel)});
        }
        try stdout.print("\n", .{});
    }
    try bw.flush();

    img.raw_image.* = try stb.load_image(filename, null);
    std.debug.print("Image: {s}\n", .{filename});
    std.debug.print("Image of size {d}x{d} with {d} channels\n", .{ img.raw_image.width, img.raw_image.height, img.raw_image.nchan });
}
