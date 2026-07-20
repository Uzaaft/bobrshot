const std = @import("std");

pub fn createModule(
    builder: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const module = builder.createModule(.{
        .root_source_file = builder.path("pkg/apple-sdk/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    return module;
}

pub fn configure(builder: *std.Build, step: *std.Build.Step.Compile) !void {
    const target = step.rootModuleTarget();
    if (!target.os.tag.isDarwin()) return error.ApplePlatformRequired;

    const libc = try std.zig.LibCInstallation.findNative(
        builder.allocator,
        builder.graph.io,
        .{
            .target = &target,
            .environ_map = &builder.graph.environ_map,
            .verbose = false,
        },
    );
    var rendered: std.Io.Writer.Allocating = .init(builder.allocator);
    defer rendered.deinit();
    try libc.render(&rendered.writer);
    const generated = builder.addWriteFiles();
    step.setLibCFile(generated.add("apple-libc.txt", rendered.written()));

    const system_include = libc.sys_include_dir orelse return error.AppleSdkHeadersNotFound;
    const sdk_usr = std.fs.path.dirname(system_include) orelse return error.AppleSdkHeadersNotFound;
    const sdk_root = std.fs.path.dirname(sdk_usr) orelse return error.AppleSdkHeadersNotFound;
    step.root_module.addSystemIncludePath(.{ .cwd_relative = system_include });
    step.root_module.addLibraryPath(.{ .cwd_relative = builder.pathJoin(&.{ sdk_usr, "lib" }) });
    step.root_module.addSystemFrameworkPath(.{
        .cwd_relative = builder.pathJoin(&.{ sdk_root, "System", "Library", "Frameworks" }),
    });
    step.root_module.linkFramework("CoreFoundation", .{});
    step.root_module.linkFramework("CoreGraphics", .{});
    step.root_module.linkFramework("ImageIO", .{});
}
