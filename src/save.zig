const std = @import("std");
const s = @import("serialize.zig");

pub const pc_save_len = s.streamedSize(Data);
comptime {
    const expected_len = 0x11550;
    if (pc_save_len != expected_len)
        @compileError(std.fmt.comptimePrint("PC save len wrong: expected 0x{x}, got 0x{x}", .{ expected_len, pc_save_len }));
}

pub const ChapterStats = struct {
    info: u32, // & 1 unlocked, & 2 completed
    overall: BattleStats,
    unk_18: [0x18]u8,
    deaths: u16,
    pad_32: [2]u8,
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
    unk_00: [0x120]u8,
    unk_120: [0x58]u8,
};

// TODO: Turn these into actual structs
pub const Data = struct {
    header: Header,
    pad_20: [0x10]u8,
    // substruct, size = 0xEE80 | FUN_00c18730
    unk_30: u32,
    play_time: u32,
    chapter: i32,
    unk_3C: u32,
    difficulty: i32,
    unk_44: [0x64]u8,
    chapter_stats: [5][20]ChapterStats,
    unk_9388: [0x5A84]u8,
    chapter_clears: u32,
    unk_EE10: [0xC]u8,
    character_model: u32,
    unk_EE20: [0x30]u8,
    unk_EE50: [0x60]u8,
    // substruct end
    // substruct, size = 0xDA0 | FUN_00c185c0
    unk_EEB0: [0x4A]u8,
    weapons: u16,
    unk_EEFC: [0x28]u8,
    character: u32,
    unk_EF28: [0x1C]u8,
    techniques: u32, // & 0x8 is Bat Within
    bought_techniques: u32,
    unk_EF4C: [0x8]u8,
    halos: u32,
    unk_EF58: u32,
    unk_EF5C: [3]i32,
    inventory: [74]u32,
    unk_F090: [0x24]u8,
    unk_F0B4: u32,
    unk_F0B8: [0xB98]u8,
    // substruct end
    // substruct, size = 0x330 | FUN_00c185c0
    chapter_overall_stats: BattleStats,
    unk_FC64: [0x18]u8,
    unk_FC7C: u16,
    pad_FC7E: [2]u8,
    unk_FC80: [0x18]u8,
    unk_FC98: u32,
    unk_FC9C: u32,
    current_verse_stats: BattleStats,
    chapter_verses_stats: [16]BattleStats,
    unk_FDF4: u32,
    unk_FDF8: u32,
    pad_FDFC: [4]u8,
    unk_FE00: ComboStats,
    pad_FF78: [8]u8,
    // substruct end
    // substruct, size = 0x15D0 | FUN_00c185c0
    unk_FF80: struct {
        unk_00: [0x20]u8,
        unk_20: [0x40]u8,
        unk_60: [0x50]u8,
    },
    unk_10030: [0x5D0]u8,
    unk_10600: u32,
    unk_10604: u32,
    unk_10608: [0xE3C]u8,
    unk_11444: u32,
    unk_11448: u32,
    unk_1144C: [0xF8]u8,
    unk_11544: u32,
    unk_11548: [0x8]u8,
    // substruct end
};

pub const Header = struct {
    magic: u32,
    unk_04: u32,
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
    comptime var type_stack: []const type = &.{Data};
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
