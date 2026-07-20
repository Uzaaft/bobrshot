pub const CFIndex = isize;
pub const CFTypeID = usize;
pub const CFNumberType = CFIndex;
pub const CGImageSourceStatus = i32;

pub const CFTypeRef = *const anyopaque;
pub const CFAllocatorRef = *const opaque {};
pub const CFDataRef = *const opaque {};
pub const CFDictionaryRef = *const opaque {};
pub const CFStringRef = *const opaque {};
pub const CFNumberRef = *const opaque {};
pub const CFBooleanRef = *const opaque {};
pub const CGImageSourceRef = *const opaque {};

pub const kCFNumberSInt64Type: CFNumberType = 4;
pub const kCGImageStatusComplete: CGImageSourceStatus = 0;

pub extern var kCFAllocatorDefault: CFAllocatorRef;
pub extern var kCFAllocatorNull: CFAllocatorRef;
pub extern var kCGImagePropertyPixelWidth: CFStringRef;
pub extern var kCGImagePropertyPixelHeight: CFStringRef;
pub extern var kCGImagePropertyOrientation: CFStringRef;
pub extern var kCGImagePropertyHasAlpha: CFStringRef;
pub extern var kCGImagePropertyProfileName: CFStringRef;

pub extern fn CFDataCreateWithBytesNoCopy(
    allocator: CFAllocatorRef,
    bytes: [*]const u8,
    length: CFIndex,
    bytes_deallocator: CFAllocatorRef,
) ?CFDataRef;
pub extern fn CFRelease(value: CFTypeRef) void;
pub extern fn CFGetTypeID(value: CFTypeRef) CFTypeID;
pub extern fn CFDictionaryGetValue(
    dictionary: CFDictionaryRef,
    key: *const anyopaque,
) ?*const anyopaque;
pub extern fn CFNumberGetTypeID() CFTypeID;
pub extern fn CFNumberGetValue(
    number: CFNumberRef,
    number_type: CFNumberType,
    value: *anyopaque,
) u8;
pub extern fn CFBooleanGetTypeID() CFTypeID;
pub extern fn CFBooleanGetValue(boolean: CFBooleanRef) u8;
pub extern fn CFStringGetTypeID() CFTypeID;

pub extern fn CGImageSourceCreateWithData(
    data: CFDataRef,
    options: ?CFDictionaryRef,
) ?CGImageSourceRef;
pub extern fn CGImageSourceGetStatus(source: CGImageSourceRef) CGImageSourceStatus;
pub extern fn CGImageSourceGetCount(source: CGImageSourceRef) usize;
pub extern fn CGImageSourceGetStatusAtIndex(
    source: CGImageSourceRef,
    index: usize,
) CGImageSourceStatus;
pub extern fn CGImageSourceCopyPropertiesAtIndex(
    source: CGImageSourceRef,
    index: usize,
    options: ?CFDictionaryRef,
) ?CFDictionaryRef;
