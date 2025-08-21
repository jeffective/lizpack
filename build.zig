//! To use this library:
//!
//! Refer to README.md.
//!
//! For developing this library:
//!
//! The default step runs all the tests. Just run `zig build`.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lizpack = b.addModule("lizpack", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{
        .root_module = lizpack,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    b.default_step.dependOn(&run_lib_unit_tests.step);
    const examples = b.createModule(.{
        .root_source_file = b.path("examples/examples.zig"),
        .target = target,
        .optimize = optimize,
    });
    const examples_tests = b.addTest(.{
        .root_module = examples,
    });
    examples_tests.root_module.addImport("lizpack", lizpack);
    const run_examples_tests = b.addRunArtifact(examples_tests);
    b.default_step.dependOn(&run_examples_tests.step);
}
