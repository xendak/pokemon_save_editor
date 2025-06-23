const pokemon = @import("pokemon_data.zig");
const pokedex = @import("pokedex.zig");
const hex_table = @import("name_table.zig");
const read = @import("utils.zig").read;
const skip = @import("utils.zig").skip;
const std = @import("std");
const print = std.debug.print;

pub const PokemonParty = struct {
    party: [6]pokemon.Pokemon,

    pub fn from_buffer(buffer: *[]const u8) PokemonParty {
        // skip(buffer, offset);
        const pokemon_count = 4;
        const pokemon_to_print = 1;
        var result: PokemonParty = .{ .party = undefined };
        for (0..pokemon_count) |p| {
            const pv = read(u32, buffer);
            const flag = read(u16, buffer);
            const checksum = read(u16, buffer);

            // needs & so it doesnt become a copy.
            var current = &result.party[p];
            current.pv = pv;
            current.flags = flag;
            current.checksum = checksum;

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

            // TODO: we dont need to re-shuffle nor unshuffle, just find the order and assign it properly.
            // const data = unshuffle(shuffled_data, pv);
            const order = current.get_block_order();

            const data_a = shuffled_data[(order[0] * 32)..][0..32];
            const data_b = shuffled_data[(order[1] * 32)..][0..32];
            const data_c = shuffled_data[(order[2] * 32)..][0..32];
            const data_d = shuffled_data[(order[3] * 32)..][0..32];

            current.a = std.mem.bytesAsValue(pokemon.Block_A, data_a).*;
            current.b = std.mem.bytesAsValue(pokemon.Block_B, data_b).*;
            current.c = std.mem.bytesAsValue(pokemon.Block_C, data_c).*;
            current.d = std.mem.bytesAsValue(pokemon.Block_D, data_d).*;

            if (p == pokemon_to_print) {
                print("\nPokemon: {}\n", .{p});
                print_block(current.a);
                print_block(current.b);
                print_block(current.c);
                print_block(current.d);
                const iv: pokemon.IVs = pokemon.IVs.init_iv(current.b.iv);
                const specie_name = pokedex.get_pokemon_name(current.a.sid) catch |err| @errorName(err);
                print("Species: {s}\n", .{specie_name});
                print("IV: {any}\n", .{iv});
                print_name(current.c.nickname, "Nickname");
                print_name(current.d.trainer_name, "OT");
            }

            var bt: [100]u8 = undefined;
            inline for (0..100) |i| {
                bt[i] = read(u8, buffer);
            }
            current.battle_stats = std.mem.bytesAsValue(pokemon.BattleStats, bt[0..]).*;
            // SKIPPING BATTLE STATS AT THE MOMENT.
            // skip(buffer, 100 * @sizeOf(u8));
        }

        return result;
    }
};

pub const SaveBlock = struct {
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

    pub fn get_gender(self: @This()) [:0]const u8 {
        const name =
            switch (self.gender) {
                0 => "Male",
                1 => "Female",
                else => "Undefined",
            };
        return name[0..];
    }

    pub fn get_language(self: @This()) [:0]const u8 {
        const language =
            switch (self.language) {
                1 => "JP",
                2 => "EN",
                else => "ERR",
            };
        return language[0..];
    }

    pub fn get_name_array(self: @This()) struct { letters: [8:0]u21, len: usize } {
        var res: [8:0]u21 = [_:0]u21{0} ** 8;
        var len: usize = 0;
        for (self.name, 0..) |l, i| {
            res[i] = hex_table.hex_to_letter(l);
            len += 1;
            if (0xFFFF == l) break;
        }
        return .{ .letters = res, .len = len };
    }

    pub fn get_name_c_string(self: @This(), allocator: std.mem.Allocator) ![:0]u8 {
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

    pub fn get_johto_badges(self: @This()) u8 {
        return @popCount(self.johto_badges);
    }
    pub fn get_kanto_badges(self: @This()) u8 {
        return @popCount(self.kanto_badges);
    }
};

pub fn get_checksum(buffer: []u8, offset: u32) u16 {
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

pub const block_detection = enum {
    FIRST,
    SECOND,
    SAME,
};

pub fn get_current_save_block(buffer: []u8) block_detection {
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

pub fn print_block(data: anytype) void {
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

    const perm = pokemon.INVERSE_PERMUTATION[@as(usize, @intCast(shift))];

    var result: [128]u8 = undefined;
    for (0..4) |i| {
        const src_index = perm[i];
        @memcpy(result[i * 32 .. i * 32 + 32], &blocks[src_index]);
    }

    return result;
}

// fn parsePokemonData(data: *const [128]u8) struct { a: Block_A, b: Block_B, c: Block_C, d: Block_D } {
//     return .{
//         .a = @bitCast(data[0..32].*),
//         .b = @bitCast(data[32..64].*),
//         .c = @bitCast(data[64..96].*),
//         .d = @bitCast(data[96..128].*),
//     };
// }
