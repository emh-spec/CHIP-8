const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("libchip8", .{
        .root_source_file = b.path("src/root.zig"),

        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "chip8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),

            .target = target,
            .optimize = optimize,
            .strip = true,
            .link_libc = true,

            .imports = &.{
                .{ .name = "chip8", .module = mod },
            },
        }),
    });

    exe.root_module.linkSystemLibrary("SDL2", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
