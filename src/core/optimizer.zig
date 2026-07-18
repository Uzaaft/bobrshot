const std = @import("std");
const media = @import("media.zig");

pub const Options = struct {
    strip_png_metadata: bool = true,
    strip_jpeg_exif: bool = true,
    strip_jpeg_xmp: bool = true,
    strip_jpeg_comments: bool = true,
};

pub const OptimizeError = error{
    OutOfMemory,
    OutputTooSmall,
    UnsupportedFormat,
    TruncatedInput,
    InvalidPngSignature,
    InvalidPngChunk,
    InvalidPngCrc,
    InvalidPngStructure,
    InvalidJpegMarker,
    InvalidJpegSegment,
    InvalidJpegStructure,
};

/// Fully validates `bytes` and returns the exact output size without allocating.
pub fn measure(bytes: []const u8, options: Options) OptimizeError!usize {
    const format = media.detectImageFormat(bytes) orelse return error.UnsupportedFormat;
    return switch (format) {
        .png => processPng(bytes, options, null),
        .jpeg => processJpeg(bytes, options, null),
        else => bytes.len,
    };
}

/// Fully validates `bytes` and writes the optimized image into caller-owned
/// memory. Returns the number of initialized bytes in `output`.
pub fn optimizeInto(bytes: []const u8, options: Options, output: []u8) OptimizeError!usize {
    const required = try measure(bytes, options);
    if (output.len < required) return error.OutputTooSmall;

    const format = media.detectImageFormat(bytes) orelse return error.UnsupportedFormat;
    return switch (format) {
        .png => processPng(bytes, options, output),
        .jpeg => processJpeg(bytes, options, output),
        else => {
            @memmove(output[0..bytes.len], bytes);
            return bytes.len;
        },
    };
}

/// Convenience API for Zig callers. C and Swift integrations should use
/// `measure` and `optimizeInto` to keep allocation ownership with the caller.
pub fn optimize(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    options: Options,
) OptimizeError![]u8 {
    const output_len = try measure(bytes, options);
    const output = allocator.alloc(u8, output_len) catch return error.OutOfMemory;
    errdefer allocator.free(output);
    std.debug.assert(try optimizeInto(bytes, options, output) == output_len);
    return output;
}

const Sink = struct {
    output: ?[]u8,
    written: usize = 0,

    fn append(self: *Sink, bytes: []const u8) OptimizeError!void {
        if (self.output) |output| {
            if (bytes.len > output.len - self.written) return error.OutputTooSmall;
            @memmove(output[self.written .. self.written + bytes.len], bytes);
        }
        self.written += bytes.len;
    }
};

const png_signature = "\x89PNG\r\n\x1a\n";

fn processPng(bytes: []const u8, options: Options, output: ?[]u8) OptimizeError!usize {
    if (bytes.len < png_signature.len) return error.TruncatedInput;
    if (!std.mem.eql(u8, bytes[0..png_signature.len], png_signature)) return error.InvalidPngSignature;

    var sink = Sink{ .output = output };
    try sink.append(png_signature);
    var offset: usize = png_signature.len;
    var chunk_index: usize = 0;
    var saw_ihdr = false;
    var saw_idat = false;
    var idat_finished = false;
    var saw_iend = false;

    while (offset < bytes.len) : (chunk_index += 1) {
        if (bytes.len - offset < 12) return error.TruncatedInput;
        const data_len_u32 = readU32Be(bytes[offset .. offset + 4]);
        const data_len: usize = @intCast(data_len_u32);
        if (data_len > bytes.len - offset - 12) return error.TruncatedInput;
        const chunk_end = offset + 12 + data_len;
        const chunk_type = bytes[offset + 4 .. offset + 8];
        if (!validPngChunkType(chunk_type)) return error.InvalidPngChunk;

        if (pngCrc32(bytes[offset + 4 .. offset + 8 + data_len]) !=
            readU32Be(bytes[offset + 8 + data_len .. chunk_end]))
        {
            return error.InvalidPngCrc;
        }

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            if (chunk_index != 0 or saw_ihdr or data_len != 13) return error.InvalidPngStructure;
            saw_ihdr = true;
        } else if (!saw_ihdr) {
            return error.InvalidPngStructure;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            if (idat_finished or saw_iend) return error.InvalidPngStructure;
            saw_idat = true;
        } else {
            if (saw_idat) idat_finished = true;
            if (std.mem.eql(u8, chunk_type, "IEND")) {
                if (!saw_idat or saw_iend or data_len != 0 or chunk_end != bytes.len) {
                    return error.InvalidPngStructure;
                }
                saw_iend = true;
            }
        }

        if (!(options.strip_png_metadata and isDiscardablePngMetadata(chunk_type))) {
            try sink.append(bytes[offset..chunk_end]);
        }
        offset = chunk_end;
    }

    if (!saw_ihdr or !saw_idat or !saw_iend) return error.InvalidPngStructure;
    return sink.written;
}

fn validPngChunkType(chunk_type: []const u8) bool {
    for (chunk_type) |byte| {
        if (!std.ascii.isAlphabetic(byte)) return false;
    }
    // The reserved bit in the third chunk-type byte must currently be zero.
    return std.ascii.isUpper(chunk_type[2]);
}

fn isDiscardablePngMetadata(chunk_type: []const u8) bool {
    return std.mem.eql(u8, chunk_type, "tEXt") or
        std.mem.eql(u8, chunk_type, "zTXt") or
        std.mem.eql(u8, chunk_type, "iTXt") or
        std.mem.eql(u8, chunk_type, "eXIf") or
        std.mem.eql(u8, chunk_type, "tIME");
}

fn processJpeg(bytes: []const u8, options: Options, output: ?[]u8) OptimizeError!usize {
    if (bytes.len < 4) return error.TruncatedInput;
    if (bytes[0] != 0xff or bytes[1] != 0xd8) return error.InvalidJpegStructure;

    var sink = Sink{ .output = output };
    try sink.append(bytes[0..2]);
    var offset: usize = 2;
    var in_scan = false;
    var saw_frame = false;
    var saw_scan = false;
    var saw_eoi = false;

    while (offset < bytes.len) {
        if (in_scan) {
            const scan_start = offset;
            while (offset < bytes.len) {
                if (bytes[offset] != 0xff) {
                    offset += 1;
                    continue;
                }
                if (offset + 1 >= bytes.len) return error.TruncatedInput;
                var marker_pos = offset + 1;
                while (marker_pos < bytes.len and bytes[marker_pos] == 0xff) : (marker_pos += 1) {}
                if (marker_pos >= bytes.len) return error.TruncatedInput;
                const code = bytes[marker_pos];
                if (code == 0x00) {
                    offset = marker_pos + 1;
                    continue;
                }
                if (code >= 0xd0 and code <= 0xd7) {
                    offset = marker_pos + 1;
                    continue;
                }
                break;
            }
            if (offset > scan_start) {
                try sink.append(bytes[scan_start..offset]);
            }
            in_scan = false;
            continue;
        }

        if (bytes[offset] != 0xff) return error.InvalidJpegMarker;
        const marker_start = offset;
        while (offset < bytes.len and bytes[offset] == 0xff) : (offset += 1) {}
        if (offset >= bytes.len) return error.TruncatedInput;
        const marker = bytes[offset];
        offset += 1;
        if (marker == 0x00 or marker == 0xff) return error.InvalidJpegMarker;

        if (marker == 0xd9) {
            try sink.append(bytes[marker_start..offset]);
            if (offset != bytes.len) return error.InvalidJpegStructure;
            saw_eoi = true;
            break;
        }
        if (marker == 0xd8 or (marker >= 0xd0 and marker <= 0xd7) or marker == 0x01) {
            return error.InvalidJpegStructure;
        }
        if (marker < 0xc0) return error.InvalidJpegMarker;
        if (bytes.len - offset < 2) return error.TruncatedInput;
        const segment_len: usize = readU16Be(bytes[offset .. offset + 2]);
        if (segment_len < 2) return error.InvalidJpegSegment;
        if (segment_len > bytes.len - offset) return error.TruncatedInput;
        const segment_end = offset + segment_len;
        const payload = bytes[offset + 2 .. segment_end];
        if (isStartOfFrame(marker)) {
            if (!validStartOfFrame(payload)) return error.InvalidJpegStructure;
            saw_frame = true;
        }
        if (marker == 0xda and (!saw_frame or !validStartOfScan(payload))) {
            return error.InvalidJpegStructure;
        }
        const discard = shouldDiscardJpegSegment(marker, payload, options);
        if (!discard) {
            try sink.append(bytes[marker_start..segment_end]);
        }
        offset = segment_end;
        if (marker == 0xda) {
            saw_scan = true;
            in_scan = true;
        }
    }

    if (!saw_scan or !saw_eoi) return error.InvalidJpegStructure;
    return sink.written;
}

fn shouldDiscardJpegSegment(marker: u8, payload: []const u8, options: Options) bool {
    if (marker == 0xfe) return options.strip_jpeg_comments;
    if (marker != 0xe1) return false;
    if (options.strip_jpeg_exif and std.mem.startsWith(u8, payload, "Exif\x00\x00")) return true;
    if (!options.strip_jpeg_xmp) return false;
    return std.mem.startsWith(u8, payload, "http://ns.adobe.com/xap/1.0/\x00") or
        std.mem.startsWith(u8, payload, "http://ns.adobe.com/xmp/extension/\x00");
}

fn isStartOfFrame(marker: u8) bool {
    return switch (marker) {
        0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf => true,
        else => false,
    };
}

fn validStartOfFrame(payload: []const u8) bool {
    if (payload.len < 9) return false;
    const component_count: usize = payload[5];
    return component_count > 0 and payload.len == 6 + 3 * component_count;
}

fn validStartOfScan(payload: []const u8) bool {
    if (payload.len < 6) return false;
    const component_count: usize = payload[0];
    return component_count > 0 and payload.len == 4 + 2 * component_count;
}

fn readU16Be(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU32Be(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}

fn updatePngCrc(crc: u32, bytes: []const u8) u32 {
    var current = crc;
    for (bytes) |byte| {
        current ^= byte;
        for (0..8) |_| {
            current = if (current & 1 != 0)
                (current >> 1) ^ 0xedb88320
            else
                current >> 1;
        }
    }
    return current;
}

fn pngCrc32(bytes: []const u8) u32 {
    return ~updatePngCrc(0xffffffff, bytes);
}

fn appendPngChunk(list: *std.ArrayList(u8), allocator: std.mem.Allocator, chunk_type: *const [4]u8, data: []const u8) !void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(data.len), .big);
    try list.appendSlice(allocator, &length);
    try list.appendSlice(allocator, chunk_type);
    try list.appendSlice(allocator, data);
    var crc: u32 = 0xffffffff;
    crc = updatePngCrc(crc, chunk_type);
    crc = updatePngCrc(crc, data);
    var checksum: [4]u8 = undefined;
    std.mem.writeInt(u32, &checksum, ~crc, .big);
    try list.appendSlice(allocator, &checksum);
}

test "PNG optimization strips textual metadata but preserves color and pixel chunks" {
    const allocator = std.testing.allocator;
    var input: std.ArrayList(u8) = .empty;
    defer input.deinit(allocator);
    try input.appendSlice(allocator, png_signature);
    try appendPngChunk(&input, allocator, "IHDR", &([_]u8{ 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0 }));
    try appendPngChunk(&input, allocator, "iCCP", "profile\x00payload");
    try appendPngChunk(&input, allocator, "tEXt", "Author\x00Bob");
    try appendPngChunk(&input, allocator, "IDAT", "pixels");
    try appendPngChunk(&input, allocator, "IEND", "");

    const result = try optimize(allocator, input.items, .{});
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "iCCP") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "profile\x00payload") != null);
    try std.testing.expectEqual(null, std.mem.indexOf(u8, result, "tEXt"));
    try std.testing.expect(std.mem.indexOf(u8, result, "pixels") != null);
    try std.testing.expect(result.len < input.items.len);
}

test "PNG validation rejects corrupted CRC and nonconsecutive IDAT chunks" {
    const allocator = std.testing.allocator;
    var input: std.ArrayList(u8) = .empty;
    defer input.deinit(allocator);
    try input.appendSlice(allocator, png_signature);
    try appendPngChunk(&input, allocator, "IHDR", &([_]u8{ 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0 }));
    try appendPngChunk(&input, allocator, "IDAT", "a");
    try appendPngChunk(&input, allocator, "tEXt", "note");
    try appendPngChunk(&input, allocator, "IDAT", "b");
    try appendPngChunk(&input, allocator, "IEND", "");
    try std.testing.expectError(error.InvalidPngStructure, optimize(allocator, input.items, .{}));

    input.items[29] ^= 1;
    try std.testing.expectError(error.InvalidPngCrc, optimize(allocator, input.items, .{}));
}

test "JPEG optimization strips selected metadata and preserves ICC and entropy data" {
    const allocator = std.testing.allocator;
    const jpeg =
        "\xff\xd8" ++
        "\xff\xe1\x00\x0cExif\x00\x00meta" ++
        "\xff\xe2\x00\x0eICC_PROFILE\x00" ++
        "\xff\xfe\x00\x09comment" ++
        "\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00" ++
        "\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00" ++
        "data\xff\x00more\xff\xd0tail" ++
        "\xff\xd9";
    const result = try optimize(allocator, jpeg, .{});
    defer allocator.free(result);
    try std.testing.expectEqual(null, std.mem.indexOf(u8, result, "Exif"));
    try std.testing.expectEqual(null, std.mem.indexOf(u8, result, "comment"));
    try std.testing.expect(std.mem.indexOf(u8, result, "ICC_PROFILE") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "data\xff\x00more\xff\xd0tail") != null);
}

test "JPEG metadata removal is optional and malformed segments are rejected" {
    const allocator = std.testing.allocator;
    const jpeg =
        "\xff\xd8\xff\xfe\x00\x05hey" ++
        "\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00" ++
        "\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00scan\xff\xd9";
    const result = try optimize(allocator, jpeg, .{ .strip_jpeg_comments = false });
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, jpeg, result);

    try std.testing.expectError(
        error.InvalidJpegSegment,
        optimize(allocator, "\xff\xd8\xff\xe1\x00\x01\xff\xd9", .{}),
    );
}

test "other recognized image formats pass through unchanged" {
    const allocator = std.testing.allocator;
    const gif = "GIF89aencoded-data";
    const result = try optimize(allocator, gif, .{});
    defer allocator.free(result);
    try std.testing.expectEqualSlices(u8, gif, result);
}

test "allocator-free measurement and output APIs agree" {
    const gif = "GIF89aencoded-data";
    try std.testing.expectEqual(gif.len, try measure(gif, .{}));

    var output: [gif.len]u8 = undefined;
    const written = try optimizeInto(gif, .{}, &output);
    try std.testing.expectEqual(gif.len, written);
    try std.testing.expectEqualSlices(u8, gif, output[0..written]);
    try std.testing.expectError(error.OutputTooSmall, optimizeInto(gif, .{}, output[0 .. output.len - 1]));
}
