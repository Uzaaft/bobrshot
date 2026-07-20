const std = @import("std");
const apple = @import("apple_sdk");
const media = @import("media.zig");

pub const InspectError = error{
    InvalidContainer,
    UnavailableProperties,
    InvalidDimensions,
    InvalidOrientation,
};

pub const Descriptor = struct {
    format: media.ImageFormat,
    width: u32,
    height: u32,
    frame_count: u32,
    orientation: u8,
    has_alpha: i8,
    has_color_profile: bool,
};

pub fn inspect(bytes: []const u8, format: media.ImageFormat) InspectError!Descriptor {
    const source_data = apple.CFDataCreateWithBytesNoCopy(
        apple.kCFAllocatorDefault,
        bytes.ptr,
        @intCast(bytes.len),
        apple.kCFAllocatorNull,
    ) orelse return error.InvalidContainer;
    defer apple.CFRelease(source_data);

    const source = apple.CGImageSourceCreateWithData(source_data, null) orelse {
        return error.InvalidContainer;
    };
    defer apple.CFRelease(source);
    if (apple.CGImageSourceGetStatus(source) != apple.kCGImageStatusComplete) {
        return error.InvalidContainer;
    }

    const frame_count = apple.CGImageSourceGetCount(source);
    if (frame_count == 0 or frame_count > std.math.maxInt(u32)) {
        return error.UnavailableProperties;
    }
    if (apple.CGImageSourceGetStatusAtIndex(source, 0) != apple.kCGImageStatusComplete) {
        return error.UnavailableProperties;
    }
    const properties = apple.CGImageSourceCopyPropertiesAtIndex(source, 0, null) orelse {
        return error.UnavailableProperties;
    };
    defer apple.CFRelease(properties);

    const width = try positiveDimension(properties, apple.kCGImagePropertyPixelWidth);
    const height = try positiveDimension(properties, apple.kCGImagePropertyPixelHeight);
    _ = std.math.mul(u64, width, height) catch return error.InvalidDimensions;

    return .{
        .format = format,
        .width = width,
        .height = height,
        .frame_count = @intCast(frame_count),
        .orientation = try orientation(properties),
        .has_alpha = optionalBoolean(properties, apple.kCGImagePropertyHasAlpha),
        .has_color_profile = containsType(
            properties,
            apple.kCGImagePropertyProfileName,
            apple.CFStringGetTypeID(),
        ),
    };
}

fn positiveDimension(properties: apple.CFDictionaryRef, key: apple.CFStringRef) InspectError!u32 {
    const value = integer(properties, key) orelse return error.InvalidDimensions;
    if (value <= 0 or value > std.math.maxInt(u32)) return error.InvalidDimensions;
    return @intCast(value);
}

fn orientation(properties: apple.CFDictionaryRef) InspectError!u8 {
    const value = integer(properties, apple.kCGImagePropertyOrientation) orelse return 0;
    if (value < 1 or value > 8) return error.InvalidOrientation;
    return @intCast(value);
}

fn integer(properties: apple.CFDictionaryRef, key: apple.CFStringRef) ?i64 {
    const value = apple.CFDictionaryGetValue(properties, key) orelse return null;
    const typed_value: apple.CFTypeRef = @ptrCast(value);
    if (apple.CFGetTypeID(typed_value) != apple.CFNumberGetTypeID()) return null;

    var result: i64 = 0;
    const number: apple.CFNumberRef = @ptrCast(value);
    if (apple.CFNumberGetValue(number, apple.kCFNumberSInt64Type, &result) == 0) return null;
    return result;
}

fn optionalBoolean(properties: apple.CFDictionaryRef, key: apple.CFStringRef) i8 {
    const value = apple.CFDictionaryGetValue(properties, key) orelse return -1;
    const typed_value: apple.CFTypeRef = @ptrCast(value);
    if (apple.CFGetTypeID(typed_value) != apple.CFBooleanGetTypeID()) return -1;
    const boolean: apple.CFBooleanRef = @ptrCast(value);
    return if (apple.CFBooleanGetValue(boolean) != 0) 1 else 0;
}

fn containsType(
    properties: apple.CFDictionaryRef,
    key: apple.CFStringRef,
    expected_type: apple.CFTypeID,
) bool {
    const value = apple.CFDictionaryGetValue(properties, key) orelse return false;
    return apple.CFGetTypeID(@ptrCast(value)) == expected_type;
}
