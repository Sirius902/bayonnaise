const std = @import("std");
const s = @import("serialize.zig");

comptime {
    inline for (.{
        .{ .T = FileData, .expected_len = 0x11550 },
        .{ .T = SystemData, .expected_len = 0x690 },
    }) |tuple| {
        const actual_len = s.streamedSize(tuple.T);
        if (actual_len != tuple.expected_len) {
            @compileError(std.fmt.comptimePrint("PC {s} len wrong: expected 0x{x}, got 0x{x}", .{
                @typeName(tuple.T),
                tuple.expected_len,
                actual_len,
            }));
        }
    }
}

pub const SystemData = struct {
    header: Header,
    steam_id: u64,
    unk_28: u32,
    unk_2C: [0xC4]u8,
    unk_F0: f32,
    unk_F4: u32,
    unk_F8: u32, // rumble & 0x80000000
    unk_FC: u32,
    unk_100: u32, // subtitles & 0x80000000
    subtitle_language: i32,
    brightness: f32,
    unk_10C: u32, // tutorial & 0x80000000
    unk_110: [0x8]u8,
    headphone_mode: u32,
    effects_volume: f32,
    music_volume: f32,
    unk_124: u32,
    unk_128: u32,
    unk_12C: i32,
    unk_130: [0x4]u8,
    unk_134: u32,
    unk_138: [0x4]u8,
    unk_13C: u32,
    unk_140: [0x10]u8,
    unk_150: [12]i32,
    unk_180: u64,
    unk_188: [63][5]u32,
    unk_674: u32,
    unk_678: bool,
    unk_67C: u32,
    unk_680: [0x10]u8,
};

pub const ChapterStats = struct {
    info: u32, // & 1 unlocked, & 2 completed
    overall: BattleStats,
    penalties: [14]u16, // [12] = deaths, [13] = red hot shots
    verses: [16]BattleStats,
    flags: u32, // & 0x40000000 is true if received platinum trophy
};

pub const BattleStats = struct {
    unk_00: u8,
    pad_01: [3]u8,
    time: u32,
    combo: u32,
    damage: u32,
    unk_10: u32,
};

pub const ComboStats = struct {
    current_slots: [6]ComboSlot,
    current_points: i32,
    unk_124: f32,
    unk_128: f32,
    unk_12C: i32, // Also current points?
    halo_multiplier: f32,
    high_points: i32,
    halo_count: u32,
    halo_timer: f32,
    previous_bonus: f32,
    is_taunting: bool,
    current_index: u32,
    total_points: i32,
    unk_150: i32,
    unk_154: i32,
    unk_158: [0x4]u8,
    unk_15C: u32,
    unk_160: u32,
    unk_164: u32,
    unk_168: bool,
    unk_16C: u32,
    unk_170: f32,
    unk_174: u32,
};

pub const ComboSlot = struct {
    is_active: bool,
    unk_04: i32,
    unk_08: i32,
    damage_type: i32,
    count: i32,
    timer: f32,
    index: i32,
    is_witch_time: bool,
    is_angered: bool,
    unk_24: i32,
    unk_28: i32,
    unk_2C: f32,
};

pub const FileData = struct {
    header: Header,
    steam_id: u64,
    pad_28: [8]u8,
    unk_30: FileDataUnkStruct30,
    unk_EEB0: FileDataUnkStructEEB0,
    unk_FC50: FileDataUnkStructFC50,
    unk_FF80: FileDataUnkStructFF80,
};

// size = 0xEE80 | memcpy at FUN_00c18730
pub const FileDataUnkStruct30 = struct {
    unk_00: u32,
    play_time: u32,
    chapter: i32,
    unk_0C: u32,
    difficulty: i32,
    unk_14: [0x64]u8,
    chapter_stats: [5][20]ChapterStats,
    unk_9358: [0xC8]u8,
    unk_9420: u32,
    unk_9424: i32,
    unk_9428: i32,
    unk_942C: i64,
    unk_9434: [12]i32,
    unk_9464: [0x4]u8,
    unk_9468: i32,
    unk_946C: i32,
    unk_9470: i64,
    unk_9478: i64,
    unk_9480: [0x5958]u8,
    unk_EDD8: i32,
    chapter_clears: u32,
    unk_EDE0: i32,
    unk_EDE4: [0x8]u8,
    character_model: u32,
    unk_EDF0: [0x30]u8,
    unk_EE20: [0x18]u8,
    unk_EE38: [13]i32,
    unk_EE6C: i32,
    unk_EE70: i32,
    unk_EE74: i32,
    unk_EE78: [0x8]u8,
};

// size = 0xDA0 | memcpy at FUN_00c185c0
pub const FileDataUnkStructEEB0 = struct {
    unk_00: i32,
    unk_04: i32,
    unk_08: i32,
    unk_0C: [13]i32,
    unk_40: i32,
    unk_44: i32,
    unk_48: [2]u8,
    weapons: u16,
    unk_4C: [4]i32,
    unk_5C: i32,
    unk_60: i32,
    unk_64: i32,
    unk_68: i32,
    unk_6C: i32,
    unk_70: [0x4]u8,
    character: u32,
    unk_78: [0xC]u8,
    unk_84: i32,
    unk_88: i32,
    unk_8C: u32,
    unk_90: u32,
    techniques: u32, // & 0x8 is Bat Within
    bought_techniques: u32,
    unk_9C: i32,
    unk_A0: u32,
    halos: u32,
    unk_A8: u32,
    unk_AC: [3]i32,
    inventory: [74]u32,
    unk_1E0: [0x24]u8,
    unk_204: u32,
    unk_208: [0xB80]u8,
    unk_D88: i32,
    unk_D8C: i32,
    unk_D90: i32,
    unk_D94: i32,
    unk_D98: [0x8]u8,
};

// size = 0x330 | memcpy at FUN_00c185c0
pub const FileDataUnkStructFC50 = struct {
    chapter_overall_stats: BattleStats,
    penalties: [14]u16,
    unk_30: [0x18]u8,
    unk_48: u32,
    unk_4C: u32,
    current_verse_stats: BattleStats,
    chapter_verses_stats: [16]BattleStats,
    unk_1A4: u32,
    unk_1A8: u32,
    pad_1AC: [4]u8,
    unk_1B0: ComboStats,
    unk_328: i32,
    pad_32C: [4]u8,
};

// size = 0x15D0 | memcpy at FUN_00c185c0
pub const FileDataUnkStructFF80 = struct {
    unk_00: struct {
        unk_00: [0x20]u8,
        unk_20: [0x40]u8,
        unk_60: [0x50]u8,
    },
    unk_B0: [0x40]u8,
    unk_F0: i32,
    unk_F4: i32,
    unk_F8: i32,
    unk_FC: i32,
    unk_100: i32,
    unk_104: i32,
    unk_108: i32,
    unk_10C: i32,
    unk_110: [0x534]u8,
    unk_644: u32,
    unk_648: [0x38]u8,
    unk_680: u32,
    unk_684: u32,
    unk_688: [0xE3C]u8,
    unk_14C4: u32,
    unk_14C8: u32,
    unk_14CC: [0xF8]u8,
    unk_15C4: u32,
    unk_15C8: [0x8]u8,
};

pub const Header = struct {
    magic: u32,
    unk_04: u32,
    unk_08: u32,
    checksums: Checksums,
    pad_18: [8]u8,
};

pub const Checksums = struct {
    low: u32,
    high: u32,
    xor: u32,
};

pub fn ChecksumReader(comptime ReaderType: type) type {
    return struct {
        wrapped_reader: ReaderType,
        checksum_state: ChecksumState = .{},
        header_state: u8 = 0,

        pub const Error = ReaderType.Error;
        pub const Reader = std.io.Reader(*Self, Error, read);

        const Self = @This();

        pub fn finalize(self: Self) error{NotFinalized}!Checksums {
            return try self.checksum_state.finalize();
        }

        pub fn read(self: *Self, dest: []u8) Error!usize {
            const read_len = try self.wrapped_reader.read(dest);

            for (dest) |b| {
                if (self.header_state < comptime s.streamedSize(Header)) {
                    self.header_state += 1;
                } else {
                    self.checksum_state.feed(b);
                }
            }

            return read_len;
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }
    };
}

pub fn ChecksumWriter(comptime WriterType: type) type {
    return struct {
        wrapped_writer: WriterType,
        checksum_state: ChecksumState = .{},
        header_state: u8 = 0,

        pub const Error = WriterType.Error;
        pub const Writer = std.io.Writer(*Self, Error, write);

        const Self = @This();

        pub fn finalize(self: Self) error{NotFinalized}!Checksums {
            return try self.checksum_state.finalize();
        }

        pub fn write(self: *Self, bytes: []const u8) Error!usize {
            for (bytes) |b| {
                if (self.header_state < comptime s.streamedSize(Header)) {
                    self.header_state += 1;
                } else {
                    self.checksum_state.feed(b);
                }
            }

            return try self.wrapped_writer.write(bytes);
        }

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }
    };
}

pub fn checksumReader(underlying_stream: anytype) ChecksumReader(@TypeOf(underlying_stream)) {
    return .{ .wrapped_reader = underlying_stream };
}

pub fn checksumWriter(underlying_stream: anytype) ChecksumWriter(@TypeOf(underlying_stream)) {
    return .{ .wrapped_writer = underlying_stream };
}

pub const ChecksumState = struct {
    sums: Checksums = .{ .low = 0, .high = 0, .xor = 0 },
    state: [4]u8 = undefined,
    index: usize = 0,

    pub fn feed(self: *ChecksumState, byte: u8) void {
        self.state[self.index] = byte;
        self.index += 1;

        if (self.index >= self.state.len) {
            self.index = 0;
            const word = @bitCast(u32, self.state);

            self.sums.low += @truncate(u16, word);
            self.sums.high += @truncate(u16, word >> @bitSizeOf(u16));
            self.sums.xor ^= word;
        }
    }

    pub fn finalize(self: ChecksumState) error{NotFinalized}!Checksums {
        if (self.index == 0) {
            return self.sums;
        } else {
            return error.NotFinalized;
        }
    }
};

test "unk and pad fields are named correctly" {
    const ExpectedTuple = std.meta.Tuple(&[_]type{ []const u8, []const u8 });
    comptime var type_stack: []const type = &.{ FileData, SystemData };
    comptime var expected_tuple: []const ExpectedTuple = &.{};

    comptime {
        while (type_stack.len > 0) {
            const T = type_stack[0];
            type_stack = type_stack[1..];

            inline for (@typeInfo(T).Struct.fields) |field| {
                if (std.mem.startsWith(u8, field.name, "unk_") or std.mem.startsWith(u8, field.name, "pad_")) {
                    const expected = std.fmt.comptimePrint("{s}.{s}{X:0>2}", .{
                        @typeName(T),
                        field.name[0..4],
                        s.streamedOffset(T, field.name),
                    });
                    const actual = @typeName(T) ++ "." ++ field.name;
                    expected_tuple = expected_tuple ++ &[_]ExpectedTuple{.{ expected, actual }};
                }

                switch (@typeInfo(field.field_type)) {
                    .Struct => {
                        type_stack = type_stack ++ &[_]type{field.field_type};
                    },
                    .Array, .Vector, .Pointer, .Optional => {
                        const Elem = std.meta.Elem(field.field_type);
                        if (@typeInfo(Elem) == .Struct) {
                            type_stack = type_stack ++ &[_]type{Elem};
                        }
                    },
                    else => {},
                }
            }
        }
    }

    inline for (expected_tuple) |tuple| {
        try std.testing.expectEqualStrings(tuple.@"0", tuple.@"1");
    }
}
