const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const windows = b.option(bool, "windows", "Target Microsoft Windows") orelse false;

    const exe = b.addExecutable(.{
        .name = "HGSS Save Editor",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,

        .target = b.resolveTargetQuery(.{
            .os_tag = if (windows) .windows else .linux,
        }),
    });

    if (windows) {
        exe.addIncludePath(b.path("./raylib/include"));
        exe.addLibraryPath(b.path("./raylib/lib"));
        b.installBinFile("./raylib/lib/raylib.dll", "raylib.dll");

        exe.linkSystemLibrary("raylib");
        exe.linkLibC();
    } else {
        exe.linkSystemLibrary("raylib");
        exe.linkLibC();
    }

    // exe.setTarget(target);

    // const mode = b.standardReleaseOptions();
    // exe.setBuildMode(mode);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    // idk why i need this? it should be doing this by default.
    if (windows) {
        run_exe.setCwd(b.path("zig-out/bin/"));
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
