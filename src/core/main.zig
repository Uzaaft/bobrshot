const std = @import("std");

pub const media = @import("media.zig");
pub const optimizer = @import("optimizer.zig");
const apple_image = @import("apple_image.zig");

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

const Status = enum(u32) {
    ok = 0,
    invalid_argument = 1,
    invalid_data = 2,
    unsupported_format = 3,
    limit_exceeded = 4,
    out_of_memory = 5,
    encode_failed = 6,
    internal = 7,
    buffer_too_small = 8,
};

const optimize_flag_only_if_smaller: u32 = 1 << 0;
const optimize_flag_strip_metadata: u32 = 1 << 1;
const optimize_flags_known = optimize_flag_only_if_smaller | optimize_flag_strip_metadata;
const optimize_input_length_max: usize = 512 * 1024 * 1024;

const OptimizeRequestV1 = extern struct {
    struct_size: u32,
    flags: u32,
    input_bytes: ?[*]const u8,
    input_length: usize,
    output_format: u8,
    quality: u8,
    effort: u8,
    reserved8: u8,
    reserved32: u32,
};

const ImageDescriptorV1 = extern struct {
    struct_size: u32,
    width: u32,
    height: u32,
    frame_count: u32,
    format: u8,
    orientation: u8,
    has_alpha: i8,
    has_color_profile: u8,
};

export fn bobrshot_image_inspect_v1(
    bytes: ?[*]const u8,
    length: usize,
    descriptor_ptr: ?*ImageDescriptorV1,
) callconv(.c) u32 {
    const descriptor = descriptor_ptr orelse return @intFromEnum(Status.invalid_argument);
    descriptor.* = std.mem.zeroes(ImageDescriptorV1);
    descriptor.struct_size = @sizeOf(ImageDescriptorV1);
    if (length == 0) return @intFromEnum(Status.invalid_data);
    const input_pointer = bytes orelse return @intFromEnum(Status.invalid_argument);
    const input = input_pointer[0..length];
    const format = media.detectImageFormat(input) orelse {
        return @intFromEnum(Status.unsupported_format);
    };
    const result = apple_image.inspect(input, format) catch {
        return @intFromEnum(Status.invalid_data);
    };
    descriptor.* = .{
        .struct_size = @sizeOf(ImageDescriptorV1),
        .width = result.width,
        .height = result.height,
        .frame_count = result.frame_count,
        .format = @intFromEnum(result.format),
        .orientation = result.orientation,
        .has_alpha = result.has_alpha,
        .has_color_profile = @intFromBool(result.has_color_profile),
    };
    return @intFromEnum(Status.ok);
}

export fn bobrshot_image_optimize_v1(
    request_ptr: ?*const OptimizeRequestV1,
    output_bytes: ?[*]u8,
    output_capacity: usize,
    output_length: ?*usize,
    output_format: ?*u8,
) callconv(.c) u32 {
    const result_length = output_length orelse return @intFromEnum(Status.invalid_argument);
    const result_format = output_format orelse return @intFromEnum(Status.invalid_argument);
    result_length.* = 0;
    result_format.* = 0;
    const request = request_ptr orelse return @intFromEnum(Status.invalid_argument);

    if (request.struct_size < @sizeOf(OptimizeRequestV1) or
        request.flags & ~optimize_flags_known != 0 or
        request.reserved8 != 0 or
        request.reserved32 != 0)
    {
        return @intFromEnum(Status.invalid_argument);
    }
    if (request.input_length == 0) return @intFromEnum(Status.invalid_data);
    if (request.input_length > optimize_input_length_max) {
        return @intFromEnum(Status.limit_exceeded);
    }
    const input_pointer = request.input_bytes orelse {
        return @intFromEnum(Status.invalid_argument);
    };
    if (request.quality > 100 or request.effort > 9) {
        return @intFromEnum(Status.invalid_argument);
    }
    if (request.quality != 0 or request.effort != 0) {
        return @intFromEnum(Status.unsupported_format);
    }

    const input = input_pointer[0..request.input_length];
    const source_format = media.detectImageFormat(input) orelse {
        return @intFromEnum(Status.unsupported_format);
    };
    if (request.output_format != 0 and request.output_format != @intFromEnum(source_format)) {
        return @intFromEnum(Status.unsupported_format);
    }
    if (output_bytes == null and output_capacity != 0) {
        return @intFromEnum(Status.invalid_argument);
    }

    const strip_metadata = request.flags & optimize_flag_strip_metadata != 0;
    const options = optimizer.Options{
        .strip_png_metadata = strip_metadata,
        .strip_jpeg_exif = strip_metadata,
        .strip_jpeg_xmp = strip_metadata,
        .strip_jpeg_comments = strip_metadata,
    };
    const output_pointer = output_bytes orelse {
        const measured_length = optimizer.measure(input, options) catch |err| {
            return @intFromEnum(statusForOptimizeError(err));
        };
        const preserve_original = request.flags & optimize_flag_only_if_smaller != 0 and
            measured_length >= input.len;
        result_length.* = if (preserve_original) input.len else measured_length;
        result_format.* = @intFromEnum(source_format);
        return @intFromEnum(Status.ok);
    };
    const output = output_pointer[0..output_capacity];
    const written = optimizer.optimizeInto(input, options, output) catch |err| {
        if (err != error.OutputTooSmall) {
            return @intFromEnum(statusForOptimizeError(err));
        }

        const measured_length = optimizer.measure(input, options) catch |measure_err| {
            return @intFromEnum(statusForOptimizeError(measure_err));
        };
        const preserve_original = request.flags & optimize_flag_only_if_smaller != 0 and
            measured_length >= input.len;
        const required_length = if (preserve_original) input.len else measured_length;
        result_length.* = required_length;
        result_format.* = @intFromEnum(source_format);
        if (!preserve_original or output_capacity < input.len) {
            return @intFromEnum(Status.buffer_too_small);
        }
        @memmove(output[0..input.len], input);
        return @intFromEnum(Status.ok);
    };

    const preserve_original = request.flags & optimize_flag_only_if_smaller != 0 and
        written >= input.len;
    if (preserve_original and written != input.len) {
        if (output_capacity < input.len) return @intFromEnum(Status.buffer_too_small);
        @memmove(output[0..input.len], input);
    }
    result_length.* = if (preserve_original) input.len else written;
    result_format.* = @intFromEnum(source_format);
    return @intFromEnum(Status.ok);
}

fn statusForOptimizeError(err: optimizer.OptimizeError) Status {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.OutputTooSmall => .buffer_too_small,
        error.UnsupportedFormat => .unsupported_format,
        error.TruncatedInput,
        error.InvalidPngSignature,
        error.InvalidPngChunk,
        error.InvalidPngCrc,
        error.InvalidPngStructure,
        error.InvalidJpegMarker,
        error.InvalidJpegSegment,
        error.InvalidJpegStructure,
        => .invalid_data,
    };
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

test "the optimization ABI measures and writes into caller memory" {
    var request = OptimizeRequestV1{
        .struct_size = @sizeOf(OptimizeRequestV1),
        .flags = optimize_flag_only_if_smaller,
        .input_bytes = "GIF89aencoded".ptr,
        .input_length = "GIF89aencoded".len,
        .output_format = 0,
        .quality = 0,
        .effort = 0,
        .reserved8 = 0,
        .reserved32 = 0,
    };
    var output_length: usize = undefined;
    var output_format: u8 = undefined;
    try std.testing.expectEqual(
        @intFromEnum(Status.ok),
        bobrshot_image_optimize_v1(&request, null, 0, &output_length, &output_format),
    );
    try std.testing.expectEqual(@as(usize, "GIF89aencoded".len), output_length);
    try std.testing.expectEqual(@intFromEnum(media.ImageFormat.gif), output_format);

    var output: ["GIF89aencoded".len]u8 = undefined;
    try std.testing.expectEqual(
        @intFromEnum(Status.ok),
        bobrshot_image_optimize_v1(&request, &output, output.len, &output_length, &output_format),
    );
    try std.testing.expectEqualSlices(u8, "GIF89aencoded", output[0..output_length]);

    request.input_length = 0;
    try std.testing.expectEqual(
        @intFromEnum(Status.invalid_data),
        bobrshot_image_optimize_v1(&request, null, 0, &output_length, &output_format),
    );
    try std.testing.expectEqual(@as(usize, 0), output_length);
    try std.testing.expectEqual(@as(u8, 0), output_format);
}

test "the optimization ABI rejects malformed requests safely" {
    var output_length: usize = 99;
    var output_format: u8 = 99;
    try std.testing.expectEqual(
        @intFromEnum(Status.invalid_argument),
        bobrshot_image_optimize_v1(null, null, 0, &output_length, &output_format),
    );
    try std.testing.expectEqual(@as(usize, 0), output_length);
    try std.testing.expectEqual(@as(u8, 0), output_format);
    try std.testing.expectEqual(
        @intFromEnum(Status.invalid_argument),
        bobrshot_image_optimize_v1(null, null, 0, null, &output_format),
    );
}

test {
    std.testing.refAllDecls(media);
}
