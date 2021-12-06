const std = @import("std");
const Allocator = std.mem.Allocator;

pub const pc_save_len = streamedSize(Data);
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
    unk_00: [4]u8,
    time: u32,
    combo: u32,
    damage: u32,
    unk_10: [4]u8,
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

    pub fn retrieve(stream: anytype) !Checksum {
        try stream.seekTo(0xC);
        const reader = stream.reader();

        return Checksum{
            .low = try reader.readIntLittle(u32),
            .high = try reader.readIntLittle(u32),
            .xor = try reader.readIntLittle(u32),
        };
    }

    pub fn compute(stream: anytype) !Checksum {
        try stream.seekTo(0x20);
        const reader = stream.reader();

        var low: u32 = 0;
        var high: u32 = 0;
        var xor: u32 = 0;

        while (true) {
            const word = reader.readIntLittle(u32) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };

            low += @truncate(u16, word);
            high += @truncate(u16, word >> @bitSizeOf(u16));
            xor ^= word;
        }

        return Checksum{
            .low = low,
            .high = high,
            .xor = xor,
        };
    }
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
                if (self.header_state < comptime streamedSize(Header)) {
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
                if (self.header_state < comptime streamedSize(Header)) {
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

fn streamedSize(comptime T: type) usize {
    comptime {
        return switch (@typeInfo(T)) {
            .Void, .Bool, .Int, .Float => @sizeOf(T),
            .Struct => |S| blk: {
                var size: usize = 0;
                inline for (S.fields) |field| {
                    if (field.is_comptime) continue;
                    size += streamedSize(field.field_type);
                }
                break :blk size;
            },
            .Array => |A| A.len * streamedSize(A.child),
            else => @compileError("unsupported type: " ++ @typeName(T)),
        };
    }
}

fn streamedOffset(comptime T: type, comptime field_name: []const u8) usize {
    comptime {
        var offset: usize = 0;
        inline for (@typeInfo(T).Struct.fields) |field| {
            if (field.is_comptime) continue;
            if (std.mem.eql(u8, field.name, field_name)) return offset;
            offset += streamedSize(field.field_type);
        }
        @compileError("no field \"" ++ field_name ++ "\" on type \"" ++ @typeName(T) ++ "\"");
    }
}

fn DeserializeError(comptime ReaderType: type) type {
    return ReaderType.Error || error{EndOfStream} || Allocator.Error;
}

fn deserializeInto(comptime T: type, t: *T, reader: anytype) !void {
    switch (@typeInfo(T)) {
        .Void => {},
        .Bool => t.* = try reader.readByte() != 0,
        .Int, .Float => t.* = try reader.readInt(T, std.builtin.Endian.Little),
        .Struct => |S| {
            inline for (S.fields) |field| {
                if (field.is_comptime) continue;
                try deserializeInto(field.field_type, &@field(t.*, field.name), reader);
            }
        },
        .Array => |A| {
            switch (A.child) {
                u8 => {
                    if ((try reader.readAll(t)) < A.len) {
                        return error.EndOfStream;
                    }
                },
                else => {
                    for (t) |*v| {
                        try deserializeInto(A.child, v, reader);
                    }
                },
            }
        },
        else => @compileError("unsupported type: " ++ @typeName(T)),
    }
}

pub fn deserialize(reader: anytype, allocator: Allocator) DeserializeError(@TypeOf(reader))!*Data {
    var data = try allocator.create(Data);
    errdefer allocator.destroy(data);

    inline for (comptime std.meta.fields(Data)) |field| {
        if (field.is_comptime) continue;
        try deserializeInto(field.field_type, &@field(data.*, field.name), reader);
    }

    return data;
}

test "unk fields are named correctly" {
    const ExpectedTuple = std.meta.Tuple(&[_]type{ []const u8, []const u8 });
    comptime var type_stack: []const type = &.{Data};
    comptime var expected_tuple: []const ExpectedTuple = &.{};

    comptime {
        while (type_stack.len > 0) {
            const T = type_stack[0];
            type_stack = type_stack[1..];

            inline for (@typeInfo(T).Struct.fields) |field| {
                if (std.mem.startsWith(u8, field.name, "unk_")) {
                    const expected = std.fmt.comptimePrint("{s}.unk_{X:0>2}", .{
                        @typeName(T),
                        streamedOffset(T, field.name),
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
