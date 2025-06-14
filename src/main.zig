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
const expect = std.testing.expectEqual;

// Battle Points
// 0x5bb8 u16

// Footer Start 0xf618
// Footer Size 0x10
// Checksum(u16) => 0xf626

const EVs = extern struct {
    hp: u8,
    atk: u8,
    def: u8,
    speed: u8,
    sp_atk: u8,
    sp_def: u8,
};

const ContestStats = extern struct {
    cool: u8,
    beauty: u8,
    cute: u8,
    smart: u8,
    tough: u8,
};

const Block_A = extern struct {
    sid: u16,
    item: u16,
    trainer_id: u16,
    secret_id: u16,
    exp: u32,
    friendship: u8,
    ability: u8,
    mark: u8,
    origin: u8,
    ev: EVs,
    contest_stats: ContestStats,

    // Contest Score Modifier
    sheen: u8,
    ribbons: u32,
};

const PokemonMoves = extern struct {
    move_1: u8,
    move_2: u8,
    move_3: u8,
    move_4: u8,
};

const IVs = struct {
    hp: u8,
    atk: u8,
    def: u8,
    speed: u8,
    sp_atk: u8,
    sp_def: u8,
    is_egg: bool,
    is_nicknamed: bool,

    pub fn init_iv(extern_iv: u32) IVs {
        return IVs{
            .hp = @truncate((extern_iv >> 0) & 0x1F),
            .atk = @truncate((extern_iv >> 5) & 0x1F),
            .def = @truncate((extern_iv >> 10) & 0x1F),
            .speed = @truncate((extern_iv >> 15) & 0x1F),
            .sp_atk = @truncate((extern_iv >> 20) & 0x1F),
            .sp_def = @truncate((extern_iv >> 25) & 0x1F),
            .is_egg = (extern_iv >> 30) & 0x1 != 0,
            .is_nicknamed = (extern_iv >> 31) & 0x1 != 0,
        };
    }
};

const Moveset = extern struct {
    move_info: [4]u16,
    pp_info: [4]u8,
    pp_up: [4]u8,

    // fn get_move_name(self: @This()) []const u8 {}
};

const Block_B = extern struct {
    // moves: [4]PokemonMoves,
    // movesInfo: [4]u16,
    // pp: [4]u8,
    // pp_up: [4]u8,
    moveset: Moveset,

    // expand =>  0-29 = iv, 30 isEgg, 31 isNickname
    // iv: IVs,
    iv: u32,
    ribbons: u32,

    // expand => 0 fateful, 1 female, 2 gender unknown, 3-7 Forms( << 3)
    flags: u8,
    shiny_leaves: u8,
    unknown: u8,

    // tentative
    egg_location: u16,
    met_location: u16,
};

const Block_C = extern struct {
    // 10 en, 5 jp/kr
    // + sentinel
    nickname: [11]u16,
    unknown: u8,
    game_origin: u8,
    ribbons: u32,
    unused: u32,
};

const Block_D = extern struct {
    trainer_name: [8]u16,
    date_egg: u32,
    date_met: u32,

    //tentative
    dp_egg_location: u16,
    dp_met_location: u16,
    pokerus: u8,
    dp_pokeball: u8,

    // expand => 0-6 met level, 7 female OT gender??
    flags: u8,
    encounter_type: u8,

    pokeball: u8,
    walking_pokemon_mood: u8,
};

const BattleStats = extern struct {
    // expand => 0-2 (asleep 0-7 rounds), 3 poison, 4 burn, 5 frozen, 6 paralyzed, 7 toxic
    state: u8,
    unknown_flags: u8,
    unknown: u16,
    level: u8,
    // wtf is this
    seals: u8,
    hp: u16,
    max_hp: u16,
    atk: u16,
    def: u16,
    speed: u16,
    sp_atk: u16,
    sp_def: u16,

    mail: [56]u8,
    seal_cord: [24]u8,
};

const Pokemon = struct {
    pv: u32,
    flags: u16,
    checksum: u16,
    a: Block_A,
    b: Block_B,
    c: Block_C,
    d: Block_D,
    battle_stats: BattleStats,
};

fn read(comptime T: type, cursor: *[]const u8) T {
    const size = @sizeOf(T);
    const value = std.mem.readInt(T, cursor.*[0..size], .little);
    cursor.* = cursor.*[size..];
    return value;
}
fn skip(cursor: *[]const u8, skip_bytes: usize) void {
    cursor.* = cursor.*[skip_bytes..];
}

const PokemonParty = struct {
    party: [6]Pokemon,

    pub fn from_buffer(buffer: *[]const u8) PokemonParty {
        // skip(buffer, offset);
        const pokemon_count = 4;
        const pokemon_to_print = 1;
        const result: PokemonParty = .{ .party = undefined };
        for (0..pokemon_count) |p| {
            const pv = read(u32, buffer);
            const flag = read(u16, buffer);
            const checksum = read(u16, buffer);

            var seed: u32 = checksum;
            var validate_checksum: u16 = 0;
            var shuffled_data: [128]u8 = undefined;
            std.debug.assert(buffer.len > 128);
            // decrypted[1] = data[0] & data[1]
            // decrypted then goes from 0 -> 64
            const decrypted = std.mem.bytesAsSlice(u16, &shuffled_data);

            for (0..64) |i| {
                // this will overflow, so we use zig wrapping methods to truncate to 32bit again
                seed = 0x41C64E6D *% seed +% 0x00006073;
                const key = @as(u16, @truncate(seed >> 16));

                const encrypted = read(u16, buffer);
                decrypted[i] = encrypted ^ key;

                validate_checksum = validate_checksum +% decrypted[i];

                // std.mem.writeInt(u16, data[2 * i ..][0..2], decrypted, .little);
            }

            std.debug.assert(validate_checksum == checksum);

            print("\npv: 0x{X:0>8}, checksum: 0x{X:0>4} | 0b{b:0>8}\n", .{ pv, checksum, flag });
            const data = unshuffle(shuffled_data, pv);

            const data_a = data[0..32];
            const data_b = data[32..64];
            const data_c = data[64..96];
            const data_d = data[96..128];

            const a = std.mem.bytesAsValue(Block_A, data_a).*;
            const b = std.mem.bytesAsValue(Block_B, data_b).*;
            const c = std.mem.bytesAsValue(Block_C, data_c).*;
            const d = std.mem.bytesAsValue(Block_D, data_d).*;

            if (p == pokemon_to_print) {
                print("\nPokemon: {}\n", .{p});
                print_block(a);
                print_block(b);
                print_block(c);
                print_block(d);
                const iv: IVs = IVs.init_iv(b.iv);
                print("IV: {any}\n", .{iv});
                print_name(c.nickname, "Nickname");
                print_name(d.trainer_name, "OT");
            }

            // SKIPPING BATTLE STATS AT THE MOMENT.
            skip(buffer, 100 * @sizeOf(u8));
        }

        return result;
    }
};

fn print_name(code: anytype, description: []const u8) void {
    const T = @TypeOf(code);
    const T_info = @typeInfo(T);
    comptime {
        std.debug.assert(T_info == .array);
    }
    const len = T_info.array.len;
    var i: usize = 0;

    var name: [len]u21 = undefined;
    for (0..len) |_| {
        if (code[i] == 0xFFFF) {
            name[i] = 0;
            break;
        }
        name[i] = hex_table.hex_to_letter(code[i]);
        i += 1;
    }

    print("{s}: {u}\n", .{ description, name[0..i] });
}

fn print_block(data: anytype) void {
    const fields = @typeInfo(@TypeOf(data)).@"struct".fields;
    print("{}: \n", .{@TypeOf(data)});
    inline for (fields) |field| {
        const value = @field(data, field.name);
        const ti = @typeInfo(@TypeOf(value));
        switch (ti) {
            .@"struct" => {
                print("  {s}: [\n", .{field.name});
                defer print("  ]\n", .{});
                const nested_fields = ti.@"struct".fields;
                inline for (nested_fields) |nested_field| {
                    const nested_value = @field(value, nested_field.name);
                    print("    {s}: {any}\n", .{ nested_field.name, nested_value });
                }
            },
            else => print("  {s}: {any}\n", .{ field.name, value }),
        }
    }
    print(":{} \n", .{@TypeOf(data)});
}

fn unshuffle(data: [128]u8, pv: u32) [128]u8 {
    const shift = ((pv & 0x3E000) >> 0xD) % 24;

    var blocks: [4][32]u8 = undefined;
    for (0..4) |i| {
        @memcpy(&blocks[i], data[i * 32 .. i * 32 + 32]);
    }

    const perm = INVERSE_PERMUTATION[@as(usize, @intCast(shift))];

    var result: [128]u8 = undefined;
    for (0..4) |i| {
        const src_index = perm[i];
        @memcpy(result[i * 32 .. i * 32 + 32], &blocks[src_index]);
    }

    return result;
}

fn parsePokemonData(data: *const [128]u8) struct { a: Block_A, b: Block_B, c: Block_C, d: Block_D } {
    return .{
        .a = @bitCast(data[0..32].*),
        .b = @bitCast(data[32..64].*),
        .c = @bitCast(data[64..96].*),
        .d = @bitCast(data[96..128].*),
    };
}

const INVERSE_PERMUTATION = [24][4]u8{
    // Shift 00: ABCD -> ABCD
    .{ 0, 1, 2, 3 }, // ✓ Correct
    // Shift 01: ABDC -> ABDC
    .{ 0, 1, 3, 2 }, // ✓ Correct
    // Shift 02: ACBD -> ACBD
    .{ 0, 2, 1, 3 }, // ✓ Correct
    // Shift 03: ACDB -> ACDB (NOT ADBC!)
    .{ 0, 2, 3, 1 }, // Fixed: was .{ 0, 3, 1, 2 }
    // Shift 04: ADBC -> ADBC (NOT ACDB!)
    .{ 0, 3, 1, 2 }, // Fixed: was .{ 0, 2, 3, 1 }
    // Shift 05: ADCB -> ADCB
    .{ 0, 3, 2, 1 }, // ✓ Correct
    // Shift 06: BACD -> BACD
    .{ 1, 0, 2, 3 }, // ✓ Correct
    // Shift 07: BADC -> BADC
    .{ 1, 0, 3, 2 }, // ✓ Correct
    // Shift 08: BCAD -> BCAD (NOT CABD!)
    .{ 1, 2, 0, 3 }, // Fixed: was .{ 2, 0, 1, 3 }
    // Shift 09: BCDA -> BCDA (NOT DABC!)
    .{ 1, 2, 3, 0 }, // Fixed: was .{ 3, 0, 1, 2 }
    // Shift 10: BDAC -> BDAC (NOT CADB!)
    .{ 1, 3, 0, 2 }, // Fixed: was .{ 2, 0, 3, 1 }
    // Shift 11: BDCA -> BDCA (NOT DACB!)
    .{ 1, 3, 2, 0 }, // Fixed: was .{ 3, 0, 2, 1 }
    // Shift 12: CABD -> CABD (NOT BCAD!)
    .{ 2, 0, 1, 3 }, // Fixed: was .{ 1, 2, 0, 3 }
    // Shift 13: CADB -> CADB (NOT BDAC!)
    .{ 2, 0, 3, 1 }, // Fixed: was .{ 1, 3, 0, 2 }
    // Shift 14: CBAD -> CBAD
    .{ 2, 1, 0, 3 }, // ✓ Correct
    // Shift 15: CBDA -> CBDA (NOT DBAC!)
    .{ 2, 1, 3, 0 }, // Fixed: was .{ 3, 1, 0, 2 }
    // Shift 16: CDAB -> CDAB
    .{ 2, 3, 0, 1 }, // Fixed: was .{ 2, 1, 3, 0 }
    // Shift 17: CDBA -> CDBA (NOT DCAB!)
    .{ 2, 3, 1, 0 }, // Fixed: was .{ 3, 1, 2, 0 }
    // Shift 18: DABC -> DABC (NOT BCDA!)
    .{ 3, 0, 1, 2 }, // Fixed: was .{ 1, 2, 3, 0 }
    // Shift 19: DACB -> DACB (NOT BDCA!)
    .{ 3, 0, 2, 1 }, // Fixed: was .{ 1, 3, 2, 0 }
    // Shift 20: DBAC -> DBAC (NOT CBDA!)
    .{ 3, 1, 0, 2 }, // Fixed: was .{ 2, 3, 0, 1 }
    // Shift 21: DBCA -> DBCA
    .{ 3, 1, 2, 0 }, // Fixed: was .{ 3, 2, 0, 1 }
    // Shift 22: DCAB -> DCAB (NOT CDBA!)
    .{ 3, 2, 0, 1 }, // Fixed: was .{ 2, 3, 1, 0 }
    // Shift 23: DCBA -> DCBA
    .{ 3, 2, 1, 0 }, // ✓ Correct
};

// const INVERSE_PERMUTATION = [24][4]u8{
//     // Block Order -> ABCD
//     // 00: ABCD       // 01: ABDC
//     .{ 0, 1, 2, 3 }, .{ 0, 1, 3, 2 },
//     // 02: ACBD       // 03: ADBC
//     .{ 0, 2, 1, 3 }, .{ 0, 2, 3, 1 },
//     // 04: ACDB       // 05: ADCB
//     .{ 0, 3, 1, 2 }, .{ 0, 3, 2, 1 },
//     // 06: BACD       // 07: BADC
//     .{ 1, 0, 2, 3 }, .{ 1, 0, 3, 2 },
//     // 08: BCAD       // 09: BDAC
//     .{ 1, 2, 0, 3 }, .{ 1, 2, 3, 0 },
//     // 10: BCDA       // 11: BDCA
//     .{ 1, 3, 0, 2 }, .{ 1, 3, 2, 0 },
//     // 12: CABD       // 13: CADB
//     .{ 2, 0, 1, 3 }, .{ 2, 0, 3, 1 },
//     // 14: CBAD       // 15: CDBA
//     .{ 2, 1, 0, 3 }, .{ 2, 1, 3, 0 },
//     // 16: CDAB       // 17: CBDA
//     .{ 2, 3, 0, 1 }, .{ 2, 3, 1, 0 },
//     // 18: DABC       // 19: DACB
//     .{ 3, 0, 1, 2 }, .{ 3, 0, 2, 1 },
//     // 20: DBAC       // 21: DCAB
//     .{ 3, 1, 0, 2 }, .{ 3, 1, 2, 0 },
//     // 22: DBCA       // 23: DCBA
//     .{ 3, 2, 0, 1 }, .{ 3, 2, 1, 0 },
// };

const SaveBlock = struct {
    // 5 jp/kr ? TODO: convert into proper string, let me deal with converting
    // back and forth in another class
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
        print("0x{X:0>4} ({}) > 0x{X:0>4} ({})\n", .{ footer1, footer1, footer2, footer2 });
        return .FIRST;
    }
    if (footer2 > footer1) {
        print("0x{X:0>4} ({}) < 0x{X:0>4} ({})\n", .{ footer1, footer1, footer2, footer2 });
        return .SECOND;
    }
    print("0x{X:0>4} ({}) = 0x{X:0>4} ({})\n", .{ footer1, footer1, footer2, footer2 });
    return .SAME;
}

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

    const current_block = get_current_save_block(&buffer);
    const offset: u32 = switch (current_block) {
        block_detection.FIRST => 0x0,
        block_detection.SECOND => 0x40000,
        block_detection.SAME => 0x0,
    };
    print("SaveBlock: {s}\nOffset: 0x{X:0>6}\n", .{ @tagName(current_block), offset });

    // TODO: create a save_offset structure
    const t_f: usize = @intCast(offset + 0x64);

    var party_block: []const u8 = buffer[t_f + 0x34 ..];

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
        .party = PokemonParty.from_buffer(&party_block),

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
    print("Language        :\t{s}:\t0x{X:0>2}\n", .{ save_block.get_language(), save_block.language });
    print("\n", .{});
    print("Name            :\t{s}\n", .{p_name});
    print("Array           :\t{u}\n", .{save_block.get_name_array().letters});
    print("Trainer ID      :\t{}:\t0x{X}\n", .{ save_block.trainer_id, save_block.trainer_id });
    print("Secret  ID      :\t{}:\t0x{X}\n", .{ save_block.secret_id, save_block.secret_id });
    print("Gender          :\t{s}:\t0x{X:0>2}\n", .{ save_block.get_gender(), save_block.gender });

    print("Money           :\t{}:\t0x{X:0>8}\n", .{ save_block.money, save_block.money });
    print("Coins           :\t{}:\t0x{X:0>2}\n", .{ save_block.coins, save_block.coins });
    print("Battle Points   :\t{}:\t0x{X:0>2}\n", .{ save_block.battle_points, save_block.battle_points });
    print("Party Size      :\t{}:\t0x{X:0>2}\n", .{ save_block.party_size, save_block.party_size });

    print("Johto Badges    :\t{}:\t0x{X:0>2}\n", .{ save_block.get_johto_badges(), save_block.johto_badges });
    print("Kanto Badges    :\t{}:\t0x{X:0>2}\n", .{ save_block.get_kanto_badges(), save_block.kanto_badges });
    print("Avatar          :\t{}:\t0x{X:0>2}\n", .{ save_block.sprite, save_block.sprite });
    print("Version         :\t{}:\t0x{X:0>2}\n", .{ save_block.version, save_block.version });
    print("H:M:S           :\t{}:{}:{}|\t0x{X:0>2}\n", .{ save_block.hours, save_block.minutes, save_block.seconds, save_block.hours });

    print("Coord X,Y:      :\t{},{}\n", .{ save_block.x, save_block.y });

    print("Checksum        :\t{}:\t0x{X:0>4}\n", .{ checksum, checksum });
    print("New Checksum    :\t{}:\t0x{X:0>4}\n", .{ simulated_checksum, simulated_checksum });

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
