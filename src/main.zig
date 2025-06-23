const hex_table = @import("name_table.zig");
const save_block = @import("save_block.zig");
const read = @import("utils.zig").read;
const skip = @import("utils.zig").skip;

const rl = @cImport({
    @cInclude("raylib.h");
});

// DEBUG:
const on_window = false;

const fs = std.fs;
const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const expect = std.testing.expectEqual;

// Battle Points
// 0x5bb8 u16

// Footer Start 0xf618
// Footer Size 0x10
// Checksum(u16) => 0xf626

pub fn main() anyerror!void {
    const project_root_c_string = std.c.getenv("PROJECT_ROOT") orelse ".";
    const project_root = std.mem.span(project_root_c_string);

    var gpa = std.heap.GeneralPurposeAllocator(std.heap.GeneralPurposeAllocatorConfig{
        .safety = true,
        .never_unmap = true,
        .retain_metadata = true,
        .verbose_log = false,
    }){};
    defer {
        const check = gpa.deinit();
        std.debug.print("\nGpa check = {any}\n", .{check});
    }
    const allocator = gpa.allocator();

    // TODO: remove GPA on release
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var dir_path: []const u8 = undefined;
    defer if (args.len <= 1) allocator.free(dir_path);

    var file_name: []const u8 = undefined;

    if (args.len > 1) {
        dir_path = std.fs.path.dirname(args[1]) orelse ".";
        file_name = std.fs.path.basename(args[1]);
    } else {
        dir_path = try std.fs.path.join(allocator, &[_][]const u8{
            project_root,
            "saves",
        });

        // const stdin = try std.io.getStdIn().reader().readUntilDelimiterAlloc(allocator, '\n', 4096);
        file_name = "jp.sav";
    }
    print("PATH: {s}\n", .{dir_path});
    print("NAME: {s}\n\n", .{file_name});

    var save_dir = try fs.cwd().openDir(dir_path, .{});
    defer save_dir.close();

    const save_file: fs.File = try save_dir.openFile(file_name, .{});
    defer save_file.close();

    // 7x letters for name (0, 1)  + Sentinel + u16 Trainer ID + u16 Secret ID
    const num_bytes = 1024 * 512; // 512kb
    var buffer: [num_bytes]u8 = undefined;

    // try save_file.seekTo(0x64);
    _ = try save_file.read(&buffer);
    // TODO: error handling

    const current_block = save_block.get_current_save_block(&buffer);
    const offset: u32 = switch (current_block) {
        save_block.block_detection.FIRST => 0x0,
        save_block.block_detection.SECOND => 0x40000,
        save_block.block_detection.SAME => 0x0,
    };
    print("SaveBlock: {s}\nOffset: 0x{X:0>6}\n", .{ @tagName(current_block), offset });

    // TODO: create a save_offset structure
    const t_f: usize = @intCast(offset + 0x64);

    var party_block: []const u8 = buffer[t_f + 0x34 ..];

    var save = save_block.SaveBlock{
        .name = blk: {
            var name: [8]u16 = undefined;
            inline for (0..8) |i| {
                var pair: [2]u8 = .{ buffer[t_f + 2 * i], buffer[t_f + 2 * i + 1] };

                name[i] = std.mem.readInt(u16, &pair, .little);
            }
            break :blk name;
        },
        .trainer_id = std.mem.readInt(u16, buffer[t_f + 16 ..][0..2], .little),
        .secret_id = std.mem.readInt(u16, buffer[t_f + 18 ..][0..2], .little),
        .money = std.mem.readInt(u32, buffer[t_f + 20 ..][0..4], .little),
        .gender = buffer[t_f + 24],
        .language = buffer[t_f + 25],
        .johto_badges = buffer[t_f + 26],
        .sprite = buffer[t_f + 27],
        .version = buffer[t_f + 28],
        .game_clear = buffer[t_f + 29],
        .national_dex = buffer[t_f + 30],
        .kanto_badges = buffer[t_f + 31],
        .coins = std.mem.readInt(u16, buffer[t_f + 32 ..][0..2], .little),
        .hours = std.mem.readInt(u16, buffer[t_f + 34 ..][0..2], .little),
        .minutes = buffer[t_f + 36],
        .seconds = buffer[t_f + 37],
        .battle_points = std.mem.readInt(u16, buffer[offset + 0x5bb8 ..][0..2], .little),

        .party_size = buffer[t_f + 0x30],
        .party = save_block.PokemonParty.from_buffer(&party_block),

        .x = buffer[offset + 0x123C],
        .y = buffer[offset + 0x1240],
        .map = "test",
    };

    // // "AAAABAAA"
    // save_block.name[4] = save_block.name[4] + 1;

    const checksum: u16 = std.mem.readInt(u16, buffer[offset + 0xf626 ..][0..2], .little);
    // Check if checksum will match the change
    // buffer[0x6C] = buffer[0x6C] + 1;
    // buffer[0x40088] = 0x03;
    const simulated_checksum: u16 = save_block.get_checksum(&buffer, offset);

    const p_name = try save.get_name_c_string(allocator);
    defer allocator.free(p_name);
    print("Language        :\t{s}:\t0x{X:0>2}\n", .{ save.get_language(), save.language });
    print("\n", .{});
    print("Name            :\t{s}\n", .{p_name});
    print("Array           :\t{u}\n", .{save.get_name_array().letters});
    print("Trainer ID      :\t{}:\t0x{X}\n", .{ save.trainer_id, save.trainer_id });
    print("Secret  ID      :\t{}:\t0x{X}\n", .{ save.secret_id, save.secret_id });
    print("Gender          :\t{s}:\t0x{X:0>2}\n", .{ save.get_gender(), save.gender });

    print("Money           :\t{}:\t0x{X:0>8}\n", .{ save.money, save.money });
    print("Coins           :\t{}:\t0x{X:0>2}\n", .{ save.coins, save.coins });
    print("Battle Points   :\t{}:\t0x{X:0>2}\n", .{ save.battle_points, save.battle_points });
    print("Party Size      :\t{}:\t0x{X:0>2}\n", .{ save.party_size, save.party_size });

    print("Johto Badges    :\t{}:\t0x{X:0>2}\n", .{ save.get_johto_badges(), save.johto_badges });
    print("Kanto Badges    :\t{}:\t0x{X:0>2}\n", .{ save.get_kanto_badges(), save.kanto_badges });
    print("Avatar          :\t{}:\t0x{X:0>2}\n", .{ save.sprite, save.sprite });
    print("Version         :\t{}:\t0x{X:0>2}\n", .{ save.version, save.version });
    print("H:M:S           :\t{}:{}:{}|\t0x{X:0>2}\n", .{ save.hours, save.minutes, save.seconds, save.hours });

    print("Coord X,Y:      :\t{},{}\n", .{ save.x, save.y });

    print("Checksum        :\t{}:\t0x{X:0>4}\n", .{ checksum, checksum });
    print("New Checksum    :\t{}:\t0x{X:0>4}\n", .{ simulated_checksum, simulated_checksum });

    print("\n\ndata: {*}\n", .{&buffer});
    print("Johto: {b}\t", .{save.johto_badges});
    print("Kanto: {b}\n", .{save.kanto_badges});

    print("\n", .{});

    // save.party[0].a.ev.hp = 200;
    // save_block.print_block(save.party.party[1].a);
    // save.party.party[1].a.ev.hp = 200;
    // save_block.print_block(save.party.party[1].a);

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

            rl.DrawText(p_name, 50, 50, 20, rl.BLACK);
        }
    }

    print("HGSS Save Editor", .{});
}
