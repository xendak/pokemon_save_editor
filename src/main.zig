const rl = @cImport({
    @cInclude("raylib.h");
});

const std = @import("std");
const print = std.debug.print;

const SaveData = struct {};

pub fn main() anyerror!void {
    const screen_width = 800;
    const screen_height = 450;

    rl.InitWindow(screen_width, screen_height, "HGSS Save Editor - raylib window");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(rl.WHITE);

        rl.DrawText("TODO: Pokemon HGSS Save Editor", 50, 50, 20, rl.BLACK);
    }
}
