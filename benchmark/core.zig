const std = @import("std");
const optimizer = @import("optimizer");

const payload_size = 16 * 1024 * 1024;
const iterations = 8;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const png = try makePng(allocator, payload_size);
    const output = try allocator.alloc(u8, png.len);

    std.mem.doNotOptimizeAway(try optimizer.measure(png, .{}));
    std.mem.doNotOptimizeAway(try optimizer.optimizeInto(png, .{}, output));

    const measure_start = std.Io.Clock.awake.now(init.io);
    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(try optimizer.measure(png, .{}));
    }
    const measure_duration = measure_start.untilNow(init.io, .awake);

    const write_start = std.Io.Clock.awake.now(init.io);
    for (0..iterations) |_| {
        std.mem.doNotOptimizeAway(try optimizer.optimizeInto(png, .{}, output));
    }
    const write_duration = write_start.untilNow(init.io, .awake);

    std.debug.print(
        "PNG payload: {d} MiB\nmeasure: {d:.1} MiB/s\nwrite:   {d:.1} MiB/s\n",
        .{
            payload_size / (1024 * 1024),
            throughput(measure_duration, png.len),
            throughput(write_duration, png.len),
        },
    );
}

fn throughput(duration: std.Io.Duration, bytes_per_iteration: usize) f64 {
    const bytes: f64 = @floatFromInt(bytes_per_iteration * iterations);
    const seconds = @as(f64, @floatFromInt(duration.nanoseconds)) / std.time.ns_per_s;
    return bytes / seconds / (1024 * 1024);
}

fn makePng(allocator: std.mem.Allocator, data_size: usize) ![]u8 {
    var png: std.ArrayList(u8) = .empty;
    try png.appendSlice(allocator, "\x89PNG\r\n\x1a\n");
    try appendChunk(&png, allocator, "IHDR", &([_]u8{ 0, 0, 15, 0, 0, 0, 8, 112, 8, 2, 0, 0, 0 }));
    try appendChunk(&png, allocator, "tEXt", "Generator\x00Bobrshot benchmark");
    const payload = try allocator.alloc(u8, data_size);
    @memset(payload, 0x5a);
    try appendChunk(&png, allocator, "IDAT", payload);
    try appendChunk(&png, allocator, "IEND", "");
    return png.toOwnedSlice(allocator);
}

fn appendChunk(
    png: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    chunk_type: *const [4]u8,
    data: []const u8,
) !void {
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(data.len), .big);
    try png.appendSlice(allocator, &length);
    try png.appendSlice(allocator, chunk_type);
    try png.appendSlice(allocator, data);
    var crc = std.hash.crc.Crc32.init();
    crc.update(chunk_type);
    crc.update(data);
    var checksum: [4]u8 = undefined;
    std.mem.writeInt(u32, &checksum, crc.final(), .big);
    try png.appendSlice(allocator, &checksum);
}
