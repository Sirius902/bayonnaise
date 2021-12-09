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
    unk_32: [2]u8,
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

pub const Data = struct {
    header: Header,
    unk_20: [0x14]u8,
    play_time: u32,
    chapter: i32,
    unk_3C: [0x4]u8,
    difficulty: i32,
    unk_44: [0x64]u8,
    difficulties: [5][20]ChapterStats,
    unk_9388: [0x5A84]u8,
    chapter_clears: u32,
    unk_EE10: [0xC]u8,
    character_model: u32,
    unk_EE20: [0xDA]u8,
    weapons: u16,
    unk_EEFC: [0x28]u8,
    character: u32,
    unk_EF28: [0x1C]u8,
    techniques: u32, // & 0x8 is Bat Within
    bought_techniques: u32,
    unk_EF4C: [0x8]u8,
    halos: u32,
    unk_EF58: [0xCF8]u8,
    unk_FC50: [0x1900]u8, // current chapter stats
};

pub const Header = struct {
    magic: u32,
    unk_04: [0x8]u8,
    checksum: Checksum,
    unk_18: [0x8]u8,
};

pub const Checksum = struct {
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

        pub fn finalize(self: Self) error{NotFinalized}!Checksum {
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

        pub fn finalize(self: Self) error{NotFinalized}!Checksum {
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
    checksum: Checksum = .{ .low = 0, .high = 0, .xor = 0 },
    state: [4]u8 = undefined,
    index: usize = 0,

    pub fn feed(self: *ChecksumState, byte: u8) void {
        self.state[self.index] = byte;
        self.index += 1;

        if (self.index >= self.state.len) {
            self.index = 0;
            const word = @bitCast(u32, self.state);

            self.checksum.low += @truncate(u16, word);
            self.checksum.high += @truncate(u16, word >> @bitSizeOf(u16));
            self.checksum.xor ^= word;
        }
    }

    pub fn finalize(self: ChecksumState) error{NotFinalized}!Checksum {
        if (self.index == 0) {
            return self.checksum;
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
