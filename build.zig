const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // msgpack module
    _ = b.addModule("msgpack", .{
        .root_source_file = b.path("src/root.zig"),
    });
    // msgpack module unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    b.default_step.dependOn(&run_lib_unit_tests.step);
}
