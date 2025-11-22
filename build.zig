const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("huge", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{.{
            .name = "hgsl",
            .module = b.dependency("hgsl", .{
                // .optimize = .ReleaseSmall,
                .optimize = optimize,
            }).module("hgsl"),
        }},
    });
    const glfw = b.dependency("zglfw", .{});
    lib.addImport("glfw", glfw.module("root"));
    lib.linkLibrary(glfw.artifact("glfw"));

    //NOTE: sample
    const exe = b.addExecutable(.{
        .name = "sample",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("sample/main.zig"),
            .imports = &.{.{ .name = "huge", .module = lib }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
