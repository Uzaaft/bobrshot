const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .macos,
            .os_version_min = .{ .semver = .{
                .major = 14,
                .minor = 0,
                .patch = 0,
            } },
        },
    });
    const optimize = builder.standardOptimizeOption(.{});

    const core_module = builder.createModule(.{
        .root_source_file = builder.path("src/core/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const core = builder.addLibrary(.{
        .name = "bobrshot",
        .linkage = .static,
        .root_module = core_module,
    });
    builder.installArtifact(core);

    const core_tests = builder.addTest(.{
        .root_module = core_module,
    });
    const run_core_tests = builder.addRunArtifact(core_tests);

    const c_api_test_module = builder.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const c_api_test = builder.addExecutable(.{
        .name = "c-api-test",
        .root_module = c_api_test_module,
    });
    c_api_test.root_module.addCSourceFile(.{
        .file = builder.path("test/c_api.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wpedantic" },
    });
    c_api_test.root_module.addIncludePath(builder.path("include"));
    c_api_test.root_module.linkLibrary(core);
    const run_c_api_test = builder.addRunArtifact(c_api_test);

    const test_step = builder.step("test", "Run the Zig core and C API tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_c_api_test.step);

    const xcframework = builder.addSystemCommand(&.{"macos/build-xcframework.sh"});
    xcframework.addArtifactArg(core);
    const xcframework_step = builder.step("xcframework", "Build BobrshotKit.xcframework");
    xcframework_step.dependOn(&xcframework.step);

    const app = builder.addSystemCommand(&.{
        "xcodebuild",
        "-project",
        "macos/Bobrshot.xcodeproj",
        "-scheme",
        "Bobrshot",
        "-configuration",
        "Debug",
        "-derivedDataPath",
        "zig-out/xcode",
        "build",
    });
    app.step.dependOn(&xcframework.step);
    builder.default_step.dependOn(&app.step);
    const app_step = builder.step("app", "Build the macOS application");
    app_step.dependOn(&app.step);

    const run = builder.addSystemCommand(&.{
        "open",
        "zig-out/xcode/Build/Products/Debug/Bobrshot.app",
    });
    run.step.dependOn(&app.step);
    const run_step = builder.step("run", "Build and launch Bobrshot");
    run_step.dependOn(&run.step);
}
