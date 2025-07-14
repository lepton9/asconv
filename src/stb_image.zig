const std = @import("std");
pub const c = @cImport({
    @cInclude("stb_image.h");
});

const log = std.log.scoped(.stb_image);

pub const ImageRaw = struct {
    width: i32 = 0,
    height: i32 = 0,
    nchan: i32 = 0,
    data: ?[*]u8 = null,

    pub fn deinit(self: *ImageRaw) void {
        if (self.data) |data| {
            c.stbi_image_free(data);
            self.data = null;
        }
        self.width = 0;
        self.height = 0;
        self.nchan = 0;
    }
};

pub fn load_image(filename: []const u8, nchannels: ?i32) !ImageRaw {
    var img = ImageRaw{ .nchan = nchannels orelse 3 };
    const req_nchan: i32 = if (nchannels == null) 0 else 1;
    const data = c.stbi_load(&filename[0], &img.width, &img.height, &img.nchan, req_nchan);
    if (data == null) {
        log.err("Error loading image {s}", .{filename});
        return error.LoadError;
    }
    img.data = data;
    return img;
}

pub fn load_image_from_memory(buf: []const u8) !ImageRaw {
    var img = ImageRaw{};
    const data = c.stbi_load_from_memory(&buf[0], @intCast(buf.len), &img.width, &img.height, &img.nchan, 0);
    if (data == null) {
        log.err("Error loading image from memory", .{});
        return error.LoadError;
    }
    img.data = data;
    return img;
}
