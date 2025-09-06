const std = @import("std");
const stb = @import("stb");
const corelib = @import("core");

pub const ImageRaw = stb.ImageRaw;

pub const Image = struct {
    name: []const u8,
    height: u32,
    width: u32,
    pixels: []u32,
    raw_image: *ImageRaw = undefined,
    edges: ?corelib.EdgeData = null,
    core: *corelib.Core = undefined,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, height: u32, width: u32) !*Image {
        var img = try allocator.create(Image);
        img.allocator = allocator;
        img.height = height;
        img.width = width;
        img.edges = null;
        img.pixels = try allocator.alloc(u32, height * width);
        @memset(img.pixels, 0);
        img.raw_image = try allocator.create(ImageRaw);
        img.raw_image.* = ImageRaw{};
        return img;
    }

    pub fn deinit(self: *Image) void {
        if (self.edges) |edges| {
            edges.deinit(self.allocator);
        }
        self.allocator.free(self.pixels);
        self.raw_image.deinit();
        self.allocator.destroy(self.raw_image);
        self.allocator.destroy(self);
    }

    pub fn resize(self: *Image, height: u32, width: u32) !void {
        for (self.pixels) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.pixels);
        self.pixels = try self.allocator.alloc(u32, height * width);
        @memset(self.pixels, 0);
        if (self.edges) |*edges| {
            try edges.resize(self.allocator, height, width);
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
        if (self.edges) |edges| {
            edges.deinit(self.allocator);
        }
        self.core.edge_detection = true;
        self.edges = try corelib.EdgeData.init(self.allocator, self.height, self.width);
    }

    pub fn fit_image(self: *Image) !void {
        if (self.raw_image.data == null) return error.NoImageData;
        var timer_scaling = try corelib.time.Timer.start(&self.core.stats.scaling);
        const pixels: []u32 = try convert_to_pixel_matrix(self.allocator, self.raw_image);
        defer free_pixel_mat(pixels, self.allocator);
        corelib.scale_nearest(
            pixels,
            self.pixels,
            @intCast(self.raw_image.width),
            @intCast(self.raw_image.height),
            self.width,
            self.height,
        );
        timer_scaling.stop();
        if (self.core.edge_detection) {
            var timer = try corelib.time.Timer.start(&self.core.stats.edge_detect);
            defer timer.stop();
            try corelib.calc_edges(
                self.allocator,
                self.core.*,
                self.edges.?,
                self.pixels,
                self.width,
                self.height,
            );
        }
    }

    fn get_char(self: *Image, x: usize, y: usize) []const u8 {
        if (self.core.edge_detection) {
            if (corelib.edge_char(self.edges.?, y * self.width + x, self.core.edge_chars)) |c| {
                return c;
            }
        }
        return self.core.pixel_to_char(self.pixels[y * self.width + x]);
    }

    fn pixel_to_ascii(
        self: *Image,
        buffer: *std.ArrayList(u8),
        x: usize,
        y: usize,
    ) !void {
        const c: []const u8 = self.get_char(x, y);
        if (self.core.color) switch (self.core.color_mode) {
            .color256 => try corelib.append_256_color(buffer, c, self.pixels[y * self.width + x]),
            .truecolor => try corelib.append_truecolor(buffer, c, self.pixels[y * self.width + x]),
        } else {
            try buffer.appendSlice(c);
            try buffer.appendSlice(c);
        }
    }

    pub fn to_ascii(self: *Image) ![]const u8 {
        var timer = try corelib.time.Timer.start(&self.core.stats.converting);
        defer timer.stop();
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                try self.pixel_to_ascii(&buffer, x, y);
            }
            try buffer.appendSlice("\n");
        }
        return buffer.toOwnedSlice();
    }
};

fn convert_to_pixel_matrix(allocator: std.mem.Allocator, image: *ImageRaw) ![]u32 {
    const w: usize = @intCast(image.width);
    const h: usize = @intCast(image.height);
    const channels: usize = @intCast(image.nchan);
    const pixels = try allocator.alloc(u32, h * w);
    var r_v: u8, var g_v: u8, var b_v: u8, var a_v: u8 = .{ 0, 0, 0, 0 };

    for (0..h) |y| {
        for (0..w) |x| {
            const base = (y * w + x) * channels;
            r_v = image.data.?[base];
            g_v = if (channels > 1) image.data.?[base + 1] else r_v;
            b_v = if (channels > 2) image.data.?[base + 2] else r_v;
            a_v = if (channels > 3) image.data.?[base + 3] else 0xFF;
            pixels[y * w + x] = corelib.pack_rgba(.{ r_v, g_v, b_v, a_v });
        }
    }
    return pixels;
}

fn free_pixel_mat(pixels: []u32, allocator: std.mem.Allocator) void {
    allocator.free(pixels);
}

pub fn load_image(filename: []const u8, nchannels: ?i32) !ImageRaw {
    return try stb.load_image(filename, nchannels);
}

pub fn load_image_from_memory(filename: []const u8) !ImageRaw {
    return try stb.load_image_from_memory(filename);
}
