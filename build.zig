const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const windows = b.option(bool, "windows", "Target Microsoft Windows") orelse false;

    const exe = b.addExecutable(.{
        .name = "HGSS Save Editor",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,

        .target = if (windows) b.resolveTargetQuery(.{
            .os_tag = .windows,
        }) else target,
    });

    if (windows) {
        exe.addIncludePath(b.path("./raylib/windows/include"));
        exe.addLibraryPath(b.path("./raylib/windows/lib"));
        b.installBinFile("./raylib/windows/lib/raylib.dll", "raylib.dll");
        // } else {
        // exe.addIncludePath(b.path("./raylib/linux/include"));
        // exe.addLibraryPath(b.path("./raylib/linux/lib"));
        // b.installBinFile("./raylib/linux/lib/libraylib.a", "libraylib.a");
    }

    exe.linkSystemLibrary("raylib");
    exe.linkLibC();

    // exe.setTarget(target);

    // const mode = b.standardReleaseOptions();
    // exe.setBuildMode(mode);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    // idk why i need this? it should be doing this by default.
    run_exe.setCwd(b.path("zig-out/bin/"));
    if (b.args) |args| {
        run_exe.addArgs(args);
    }
    const run_step = b.step("run", "Run the application");

    run_step.dependOn(&run_exe.step);
}
