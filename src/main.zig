const rl = @cImport({
    @cInclude("raylib.h");
});

const fs = std.fs;
const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;

const SaveData = struct {};

const on_window = false;

const MAX_LETTERS = 7;

const pokemon_name = [MAX_LETTERS:0]u8;

fn map_pokemon_letter(letter: u8) u8 {
    return switch (letter) {
        // A -> Z
        inline 43...69 => |idx| 'A' + @as(u8, idx - 43),
        // a -> z
        inline 69 + 7...69 + 26 => |idx| 'a' + @as(u8, idx - (69 + 7)),
        else => '0', // error handling or default value
    };
}

fn char_to_bytes(c: u8) [2]u8 {
    return switch (c) {
        'A' => .{ 0x2B, 0x01 }, // 0x012B little-endian
        'B' => .{ 0x2C, 0x01 }, // 0x012C little-endian
        // ... add other characters
        else => .{ 0x00, 0x00 },
    };
}
fn print_name(name: [][2]u8) pokemon_name {
    var res: pokemon_name = "abcdefg".*;

    for (name, 0..) |l, i| {
        print("\nd:{}\t{}\n", .{ l[0], l[1] });
        res[i] = map_pokemon_letter(l[0]);
    }
    return res;
}

pub fn main() anyerror!void {
    const project_root_c_string = std.c.getenv("PROJECT_ROOT") orelse ".";
    const project_root = std.mem.span(project_root_c_string);

    var arena = std.heap.GeneralPurposeAllocator(std.heap.GeneralPurposeAllocatorConfig{
        .safety = true,
        .never_unmap = true,
        .retain_metadata = true,
        .verbose_log = false,
    }){};
    defer {
        const check = arena.deinit();
        std.debug.print("\nGpa check = {any}\n", .{check});
    }

    // TODO: remove GPA on release
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();

    const dir_path = try std.fs.path.join(arena.allocator(), &[_][]const u8{
        project_root,
        "saves",
    });
    defer arena.allocator().free(dir_path);

    var save_dir = try fs.cwd().openDir(dir_path, .{});
    defer save_dir.close();

    const save_file: fs.File = try save_dir.openFile("AAAAAAA.sav", .{});
    defer save_file.close();

    const num_bytes = 14;
    var buffer: [num_bytes]u8 = undefined;

    try save_file.seekTo(0x40064);
    _ = try save_file.read(buffer[0..]);

    var name: [7][2]u8 = undefined;
    for (0..7) |i| {
        name[i][0] = buffer[2 * i];
        name[i][1] = buffer[2 * i + 1];
    }

    print("Bytes from offset 0x40064 ({} bytes):\n", .{num_bytes});

    print("Raw bytes:\n", .{});
    for (name) |pair| {
        print("{x:0>2} {x:0>2} ", .{ pair[0], pair[1] });
    }

    print("\nName:\n{s}\n", .{print_name(&name)});

    print("trying to save to file: changed.sav\n", .{});

    const output_file = try save_dir.createFile("changed.sav", .{});
    defer output_file.close();

    const new_name = "BBBBBBB";
    var new_bytes: [new_name.len * 2]u8 = undefined;
    for (new_name, 0..) |c, i| {
        const pair = char_to_bytes(c);
        new_bytes[2 * i] = pair[0];
        new_bytes[2 * i + 1] = pair[1];
    }

    try output_file.seekTo(0x40064);
    _ = try output_file.write(&new_bytes);
    try output_file.sync();

    print("\n", .{});
    if (on_window) {
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

    print("HGSS Save Editor", .{});
}
