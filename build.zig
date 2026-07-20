const std = @import("std");
const builtin = @import("builtin");
const apple_sdk = @import("pkg/apple-sdk/build.zig");

pub fn build(builder: *std.Build) !void {
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
    const native_target = builder.resolveTargetQuery(.{
        .cpu_arch = builtin.cpu.arch,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{
            .major = 14,
            .minor = 0,
            .patch = 0,
        } },
    });
    const xcode_architecture = switch (builtin.cpu.arch) {
        .aarch64 => "arm64",
        .x86_64 => "x86_64",
        else => @panic("the macOS app supports only arm64 and x86_64"),
    };
    const xcode_destination = builder.fmt("platform=macOS,arch={s}", .{xcode_architecture});

    const core = try addCore(builder, target, optimize);
    const native_core = if (target.result.cpu.arch == native_target.result.cpu.arch)
        core
    else
        try addCore(builder, native_target, optimize);
    builder.installArtifact(core);

    const core_tests = builder.addTest(.{
        .root_module = core.root_module,
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
    try apple_sdk.configure(builder, c_api_test);
    c_api_test.root_module.addCSourceFile(.{
        .file = builder.path("test/c_api.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wpedantic" },
    });
    c_api_test.root_module.addIncludePath(builder.path("include"));
    c_api_test.root_module.linkLibrary(core);
    const run_c_api_test = builder.addRunArtifact(c_api_test);

    const test_step = builder.step("test", "Run the Zig, C API, and native macOS tests");
    test_step.dependOn(&run_core_tests.step);
    test_step.dependOn(&run_c_api_test.step);

    const xcframework = builder.addSystemCommand(&.{"macos/build-xcframework.sh"});
    xcframework.addArtifactArg(native_core);
    const xcframework_step = builder.step("xcframework", "Build BobrshotKit.xcframework");
    xcframework_step.dependOn(&xcframework.step);

    const benchmark_module = builder.createModule(.{
        .root_source_file = builder.path("benchmark/core.zig"),
        .target = native_target,
        .optimize = .ReleaseFast,
    });
    benchmark_module.addImport("optimizer", builder.createModule(.{
        .root_source_file = builder.path("src/core/optimizer.zig"),
        .target = native_target,
        .optimize = .ReleaseFast,
    }));
    const benchmark = builder.addExecutable(.{
        .name = "core-benchmark",
        .root_module = benchmark_module,
    });
    const run_benchmark = builder.addRunArtifact(benchmark);
    const benchmark_step = builder.step("benchmark", "Benchmark release-optimized core processing");
    benchmark_step.dependOn(&run_benchmark.step);

    const native_tests = builder.addSystemCommand(&.{
        "xcodebuild",
        "-project",
        "macos/Bobrshot.xcodeproj",
        "-scheme",
        "Bobrshot",
        "-configuration",
        "Debug",
        "-destination",
        xcode_destination,
        "-derivedDataPath",
        "zig-out/xcode",
        "test",
    });
    native_tests.step.dependOn(&xcframework.step);
    test_step.dependOn(&native_tests.step);

    const app = builder.addSystemCommand(&.{
        "xcodebuild",
        "-project",
        "macos/Bobrshot.xcodeproj",
        "-scheme",
        "Bobrshot",
        "-configuration",
        "Debug",
        "-destination",
        xcode_destination,
        "-derivedDataPath",
        "zig-out/xcode",
        "build",
    });
    app.step.dependOn(&xcframework.step);
    builder.default_step.dependOn(&app.step);
    const app_step = builder.step("app", "Build the macOS application");
    app_step.dependOn(&app.step);

    const release_core = try addCore(builder, native_target, .ReleaseFast);
    const release_xcframework = builder.addSystemCommand(&.{"macos/build-xcframework.sh"});
    release_xcframework.addArtifactArg(release_core);
    const release_app = builder.addSystemCommand(&.{
        "xcodebuild",
        "-project",
        "macos/Bobrshot.xcodeproj",
        "-scheme",
        "Bobrshot",
        "-configuration",
        "Release",
        "-destination",
        xcode_destination,
        "-derivedDataPath",
        "zig-out/xcode-release",
        "build",
    });
    release_app.step.dependOn(&release_xcframework.step);
    const release_step = builder.step("release", "Build the app with a ReleaseFast Zig core");
    release_step.dependOn(&release_app.step);

    const run = builder.addSystemCommand(&.{
        "open",
        "zig-out/xcode/Build/Products/Debug/Bobrshot.app",
    });
    run.step.dependOn(&app.step);
    const run_step = builder.step("run", "Build and launch Bobrshot");
    run_step.dependOn(&run.step);
}

fn addCore(
    builder: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Step.Compile {
    const core = builder.addLibrary(.{
        .name = "bobrshot",
        .linkage = .static,
        .root_module = builder.createModule(.{
            .root_source_file = builder.path("src/core/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    core.root_module.addImport("apple_sdk", apple_sdk.createModule(builder, target, optimize));
    try apple_sdk.configure(builder, core);
    return core;
}
