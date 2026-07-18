const std = @import("std");

pub const media = @import("media.zig");

pub const Version = extern struct {
    major: u16,
    minor: u16,
    patch: u16,
};

const current_version = Version{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

export fn bobrshot_core_version() callconv(.c) Version {
    std.debug.assert(current_version.major == 0);
    std.debug.assert(current_version.minor == 1);
    return current_version;
}

export fn bobrshot_image_format_detect(
    bytes: ?[*]const u8,
    length: usize,
) callconv(.c) u8 {
    const data = bytes orelse return 0;
    const format = media.detectImageFormat(data[0..length]) orelse return 0;
    return @intFromEnum(format);
}

test "the C ABI reports the core version" {
    try std.testing.expectEqual(@as(usize, 6), @sizeOf(Version));
    try std.testing.expectEqual(@as(usize, 2), @alignOf(Version));

    const version = bobrshot_core_version();

    try std.testing.expectEqual(@as(u16, 0), version.major);
    try std.testing.expectEqual(@as(u16, 1), version.minor);
    try std.testing.expectEqual(@as(u16, 0), version.patch);
}

test "the C ABI detects encoded image formats" {
    const png = "\x89PNG\r\n\x1a\nrest";
    try std.testing.expectEqual(
        @intFromEnum(media.ImageFormat.png),
        bobrshot_image_format_detect(png.ptr, png.len),
    );
    try std.testing.expectEqual(@as(u8, 0), bobrshot_image_format_detect(null, 0));
}

test {
    std.testing.refAllDecls(media);
}
