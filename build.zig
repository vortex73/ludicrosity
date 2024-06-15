const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimizer = b.standardOptimizeOption(.{});
    const datetime = b.addStaticLibrary(.{
        .name = "datetime",
        .root_source_file = b.path("./zig-datetime/src/main.zig"),
        .target = b.host,
        .optimize = optimizer,
    });
    const exe = b.addExecutable(.{
        .name = "ludicrous",
        .root_source_file = b.path("src/marked.zig"),
        .target = b.host,
        .optimize = optimizer,
    });

    exe.linkLibrary(datetime);
    b.installArtifact(datetime);
    exe.linkLibC();
    exe.addIncludePath(b.path("md4c/src/"));
    exe.addCSourceFiles(.{ .files = &.{
        "md4c/src/md4c.c",
        "md4c/src/entity.c",
        "md4c/src/md4c-html.c",
    } });
    b.installArtifact(exe);
}
