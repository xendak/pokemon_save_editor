const hex_table = @import("pokemon_name_table.zig");
const rl = @cImport({
    @cInclude("raylib.h");
});

// DEBUG:
const on_window = false;

const fs = std.fs;
const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;

// Battle Points
// 0x5bb8 u16

// Footer Start 0xf618
// Footer Size 0x10
// Checksum(u16) => 0xf626

const PokemonFlags = struct {
    checksum_skip: u8,
    bad_eg: u8,
    unknown: u8,
};

const PF = union(enum) {
    CHECKSUM_SKIP: u16,
    BAD_EGG: u16,
    UNKNOWN: u16,
};

const Pokemon = struct {
    pv: u32,
    flags: u16,
    checksum: u16,
};

const PokemonParty = struct {
    party: [6]Pokemon,
};

const SaveBlock = struct {
    // name: [8][2]u8, // 7 letters and a sentinel FF FF
    name: [8]u16,
    trainer_id: u16,
    secret_id: u16,
    money: u32,
    coins: u16,
    battle_points: u16,
    gender: u8,
    sprite: u8,

    // game info
    language: u8,
    version: u8,
    game_clear: u8,

    // global
    johto_badges: u8,
    kanto_badges: u8,
    national_dex: u8,
    hours: u16,
    minutes: u8,
    seconds: u8,

    // pokemon
    party_size: u8,

    party: PokemonParty,

    // tentative
    map: []const u8,
    x: u8,
    y: u8,

    fn get_gender(self: @This()) [:0]const u8 {
        const name =
            switch (self.gender) {
                0 => "Male",
                1 => "Female",
                else => "Undefined",
            };
        return name[0..];
    }

    fn get_language(self: @This()) [:0]const u8 {
        const language =
            switch (self.language) {
                1 => "JP",
                2 => "EN",
                else => "ERR",
            };
        return language[0..];
    }

    fn get_name_array(self: @This()) struct { letters: [8:0]u21, len: usize } {
        var res: [8:0]u21 = [_:0]u21{0} ** 8;
        var len: usize = 0;
        for (self.name, 0..) |l, i| {
            res[i] = hex_table.hex_to_letter(l);
            len += 1;
            if (0xFFFF == l) break;
        }
        return .{ .letters = res, .len = len };
    }

    fn get_name_c_string(self: @This(), allocator: std.mem.Allocator) ![:0]u8 {
        const name_result = self.get_name_array(); // This returns a struct

        // Calculate needed size first
        var needed_size: usize = 0;
        for (name_result.letters[0..name_result.len]) |char| { // Use .chars field and slice to length
            needed_size += std.unicode.utf8CodepointSequenceLength(char) catch 1;
        }

        const result = try allocator.allocSentinel(u8, needed_size, 0); // const instead of var
        var stream = std.io.fixedBufferStream(result);
        const writer = stream.writer();

        for (name_result.letters[0..name_result.len]) |char| { // Use .chars field and slice to length
            try writer.print("{u}", .{char}); // Wrap char in tuple with .{char}
        }

        return result;
    }

    fn get_johto_badges(self: @This()) u8 {
        return @popCount(self.johto_badges);
    }
    fn get_kanto_badges(self: @This()) u8 {
        return @popCount(self.kanto_badges);
    }
};

fn get_checksum(buffer: []u8, offset: u32) u16 {
    var high: u8 = 0xff;
    var low: u8 = 0xff;
    // TODO: fix footer address to be less magic.
    const data: []u8 = buffer[offset .. offset + 0xf618];
    for (data) |byte| {
        var x = byte ^ high;
        x ^= (x >> 4);
        high = (low ^ (x >> 3) ^ (x << 4));
        low = (x ^ (x << 5));
    }
    return (@as(u16, high) << 8) | low;
}

const block_detection = enum {
    FIRST,
    SECOND,
    SAME,
};

fn get_current_save_block(buffer: []u8) block_detection {
    const offset = 0xf618;
    const offset2 = offset + 0x40000;
    const footer1: u32 = std.mem.readInt(u32, buffer[offset .. offset + 4], .little);
    const footer2: u32 = std.mem.readInt(u32, buffer[offset2 .. offset2 + 4], .little);

    if (footer1 > footer2) {
        print("0x{x:0>4} ({}) > 0x{x:0>4} ({})\n", .{ footer1, footer1, footer2, footer2 });
        return .FIRST;
    }
    if (footer2 > footer1) {
        print("0x{x:0>4} ({}) < 0x{x:0>4} ({})\n", .{ footer1, footer1, footer2, footer2 });
        return .SECOND;
    }
    print("0x{x:0>4} ({}) = 0x{x:0>4} ({})\n", .{ footer1, footer1, footer2, footer2 });
    return .SAME;
}

pub fn main() anyerror!void {
    const project_root_c_string = std.c.getenv("PROJECT_ROOT") orelse ".";
    const project_root = std.mem.span(project_root_c_string);

    const T = 0b1110011;
    const Z = T >> 2;
    const Q = T >> 1 & 1;
    const R = T >> 3;
    print("\nbin: {}  = {b} {b} {b}\n\n\n\n", .{ T, Q, Z, R });

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

    const current_block = get_current_save_block(&buffer);
    const offset: u32 = switch (current_block) {
        block_detection.FIRST => 0x0,
        block_detection.SECOND => 0x40000,
        block_detection.SAME => 0x0,
    };
    print("SaveBlock: {s}\nOffset: 0x{x:0>6}\n", .{ @tagName(current_block), offset });

    // TODO: create a save_offset structure
    const t_f: usize = @intCast(offset + 0x64);
    var save_block = SaveBlock{
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
        .party = undefined,

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
    const simulated_checksum: u16 = get_checksum(&buffer, offset);

    const p_name = try save_block.get_name_c_string(allocator);
    defer allocator.free(p_name);
    print("Language        :\t{s}:\t0x{x:0>2}\n", .{ save_block.get_language(), save_block.language });
    print("\n", .{});
    print("Name            :\t{s}\n", .{p_name});
    print("Array           :\t{u}\n", .{save_block.get_name_array().letters});
    print("Trainer ID      :\t{}:\t0x{x}\n", .{ save_block.trainer_id, save_block.trainer_id });
    print("Secret  ID      :\t{}:\t0x{x}\n", .{ save_block.secret_id, save_block.secret_id });
    print("Gender          :\t{s}:\t0x{x:0>2}\n", .{ save_block.get_gender(), save_block.gender });

    print("Money           :\t{}:\t0x{x:0>8}\n", .{ save_block.money, save_block.money });
    print("Coins           :\t{}:\t0x{x:0>2}\n", .{ save_block.coins, save_block.coins });
    print("Battle Points   :\t{}:\t0x{x:0>2}\n", .{ save_block.battle_points, save_block.battle_points });
    print("Party Size      :\t{}:\t0x{x:0>2}\n", .{ save_block.party_size, save_block.party_size });

    print("Johto Badges    :\t{}:\t0x{x:0>2}\n", .{ save_block.get_johto_badges(), save_block.johto_badges });
    print("Kanto Badges    :\t{}:\t0x{x:0>2}\n", .{ save_block.get_kanto_badges(), save_block.kanto_badges });
    print("Avatar          :\t{}:\t0x{x:0>2}\n", .{ save_block.sprite, save_block.sprite });
    print("Version         :\t{}:\t0x{x:0>2}\n", .{ save_block.version, save_block.version });
    print("H:M:S           :\t{}:{}:{}|\t0x{x:0>2}\n", .{ save_block.hours, save_block.minutes, save_block.seconds, save_block.hours });

    print("Coord X,Y:      :\t{},{}\n", .{ save_block.x, save_block.y });

    print("Checksum        :\t{}:\t0x{x:0>4}\n", .{ checksum, checksum });
    print("New Checksum    :\t{}:\t0x{x:0>4}\n", .{ simulated_checksum, simulated_checksum });

    print("\n\ndata: {*}\n", .{&buffer});
    print("Johto: {b}\t", .{save_block.johto_badges});
    print("Kanto: {b}\n", .{save_block.kanto_badges});

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

            rl.DrawText(p_name, 50, 50, 20, rl.BLACK);
        }
    }

    print("HGSS Save Editor", .{});
}
