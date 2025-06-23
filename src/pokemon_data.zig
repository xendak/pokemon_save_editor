pub const Pokemon = struct {
    pv: u32,
    flags: u16,
    checksum: u16,
    a: Block_A,
    b: Block_B,
    c: Block_C,
    d: Block_D,
    battle_stats: BattleStats,

    pub fn get_block_order(self: @This()) [4]u8 {
        const shift = ((self.pv & 0x3E000) >> 0xD) % 24;
        return INVERSE_PERMUTATION[@as(usize, @intCast(shift))];
    }
    pub fn get_battle_stats(self: @This(), buffer: []const u8) BattleStats {
        _ = self.battle_stats;
        _ = buffer;
        return BattleStats{};
    }
};

// ORDER -> INVERSE
// https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_data_structure_(Generation_IV)
// block shuffling
pub const INVERSE_PERMUTATION = [24][4]u8{
    .{ 0, 1, 2, 3 }, .{ 0, 1, 3, 2 }, .{ 0, 2, 1, 3 }, .{ 0, 3, 1, 2 },
    .{ 0, 2, 3, 1 }, .{ 0, 3, 2, 1 }, .{ 1, 0, 2, 3 }, .{ 1, 0, 3, 2 },
    .{ 2, 0, 1, 3 }, .{ 3, 0, 1, 2 }, .{ 2, 0, 3, 1 }, .{ 3, 0, 2, 1 },
    .{ 1, 2, 0, 3 }, .{ 1, 3, 0, 2 }, .{ 2, 1, 0, 3 }, .{ 3, 1, 0, 2 },
    .{ 2, 3, 0, 1 }, .{ 3, 2, 1, 0 }, .{ 1, 2, 3, 0 }, .{ 1, 3, 2, 0 },
    .{ 2, 1, 3, 0 }, .{ 3, 1, 2, 0 }, .{ 2, 3, 0, 1 }, .{ 3, 2, 1, 0 },
};

pub const Block_A = extern struct {
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

pub const Block_B = extern struct {
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

pub const Block_C = extern struct {
    // 10 en, 5 jp/kr
    // + sentinel
    nickname: [11]u16,
    unknown: u8,
    game_origin: u8,
    ribbons: u32,
    unused: u32,
};

pub const Block_D = extern struct {
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

pub const BattleStats = extern struct {
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

const PokemonMoves = extern struct {
    move_1: u8,
    move_2: u8,
    move_3: u8,
    move_4: u8,
};

pub const IVs = struct {
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
