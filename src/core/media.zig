const std = @import("std");

pub const probe_byte_count_max: usize = 64;

pub const ImageFormat = enum(u8) {
    png,
    jpeg,
    gif,
    webp,
    tiff,
    heic,
    heif,
};

pub fn detectImageFormat(bytes: []const u8) ?ImageFormat {
    const prefix = bytes[0..@min(bytes.len, probe_byte_count_max)];
    std.debug.assert(prefix.len <= probe_byte_count_max);
    std.debug.assert(prefix.len <= bytes.len);

    if (std.mem.startsWith(u8, prefix, "\x89PNG\r\n\x1a\n")) return .png;
    if (std.mem.startsWith(u8, prefix, "\xff\xd8\xff")) return .jpeg;
    if (std.mem.startsWith(u8, prefix, "GIF87a") or
        std.mem.startsWith(u8, prefix, "GIF89a")) return .gif;
    if (prefix.len >= 12 and
        std.mem.eql(u8, prefix[0..4], "RIFF") and
        std.mem.eql(u8, prefix[8..12], "WEBP")) return .webp;
    if (std.mem.startsWith(u8, prefix, "II\x2a\x00") or
        std.mem.startsWith(u8, prefix, "MM\x00\x2a")) return .tiff;

    return detectIsoBaseMediaImageFormat(prefix);
}

fn detectIsoBaseMediaImageFormat(prefix: []const u8) ?ImageFormat {
    if (prefix.len < 12 or !std.mem.eql(u8, prefix[4..8], "ftyp")) return null;

    var unsupported_avif_found = false;
    var generic_heif_found = false;
    var offset: usize = 8;
    while (offset + 4 <= prefix.len) : (offset += 4) {
        const brand = prefix[offset .. offset + 4];
        if (isHeicBrand(brand)) return .heic;
        if (std.mem.eql(u8, brand, "avif") or
            std.mem.eql(u8, brand, "avis")) unsupported_avif_found = true;
        if (std.mem.eql(u8, brand, "mif1") or
            std.mem.eql(u8, brand, "msf1")) generic_heif_found = true;
    }

    if (unsupported_avif_found) return null;
    return if (generic_heif_found) .heif else null;
}

fn isHeicBrand(brand: []const u8) bool {
    return std.mem.eql(u8, brand, "heic") or
        std.mem.eql(u8, brand, "heix") or
        std.mem.eql(u8, brand, "hevc") or
        std.mem.eql(u8, brand, "hevx") or
        std.mem.eql(u8, brand, "heim") or
        std.mem.eql(u8, brand, "heis");
}

test "detects common encoded image signatures" {
    try std.testing.expectEqual(ImageFormat.png, detectImageFormat("\x89PNG\r\n\x1a\nrest"));
    try std.testing.expectEqual(ImageFormat.jpeg, detectImageFormat("\xff\xd8\xff\xe0rest"));
    try std.testing.expectEqual(ImageFormat.gif, detectImageFormat("GIF87arest"));
    try std.testing.expectEqual(ImageFormat.gif, detectImageFormat("GIF89arest"));
    try std.testing.expectEqual(ImageFormat.webp, detectImageFormat("RIFF\x10\x00\x00\x00WEBPrest"));
    try std.testing.expectEqual(ImageFormat.tiff, detectImageFormat("II\x2a\x00rest"));
    try std.testing.expectEqual(ImageFormat.tiff, detectImageFormat("MM\x00\x2arest"));
}

test "detects HEIC and generic HEIF brands" {
    try std.testing.expectEqual(
        ImageFormat.heic,
        detectImageFormat("\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00heic"),
    );
    try std.testing.expectEqual(
        ImageFormat.heif,
        detectImageFormat("\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00miaf"),
    );
}

test "rejects truncated and non-image signatures" {
    try std.testing.expectEqual(null, detectImageFormat(""));
    try std.testing.expectEqual(null, detectImageFormat("\x89PNG"));
    try std.testing.expectEqual(null, detectImageFormat("RIFF\x10\x00\x00\x00AVI "));
    try std.testing.expectEqual(null, detectImageFormat("\x00\x00\x00\x18ftypisom\x00\x00\x00\x00mp42"));
    try std.testing.expectEqual(null, detectImageFormat("\x00\x00\x00\x18ftypavif\x00\x00\x00\x00mif1"));
}

test "ISO brand scanning is bounded" {
    var bytes = [_]u8{0} ** (probe_byte_count_max + 8);
    @memcpy(bytes[4..8], "ftyp");
    @memcpy(bytes[8..12], "isom");
    @memcpy(bytes[probe_byte_count_max .. probe_byte_count_max + 4], "heic");

    try std.testing.expectEqual(null, detectImageFormat(&bytes));
}
