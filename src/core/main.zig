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

test "the C ABI reports the core version" {
    try std.testing.expectEqual(@as(usize, 6), @sizeOf(Version));
    try std.testing.expectEqual(@as(usize, 2), @alignOf(Version));

    const version = bobrshot_core_version();

    try std.testing.expectEqual(@as(u16, 0), version.major);
    try std.testing.expectEqual(@as(u16, 1), version.minor);
    try std.testing.expectEqual(@as(u16, 0), version.patch);
}

test {
    std.testing.refAllDecls(media);
}
