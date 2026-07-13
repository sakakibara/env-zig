const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("env", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);

    // Generated reference docs (Zig stdlib pattern). Browse
    // `zig-out/docs/index.html` after `zig build docs`.
    const docs_obj = b.addObject(.{
        .name = "env",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const docs_install = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate API reference docs to zig-out/docs/");
    docs_step.dependOn(&docs_install.step);
}
