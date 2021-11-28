const std = @import("std");
const Allocator = std.mem.Allocator;

pub const pc_save_len = streamedSize(Data);
comptime {
    const expected_len = 0x11550;
    if (pc_save_len != expected_len)
        @compileError(std.fmt.comptimePrint("PC save len wrong: expected 0x{x}, got 0x{x}", .{ expected_len, pc_save_len }));
}

pub const Data = struct {
    header: Header,
    unk_18: [0x1C]u8,
    play_time: u32,
    unk_38: [0xEEEC]u8,
    character: u32,
    unk_EF28: [0x2C]u8,
    halos: u32,
    unk_EF58: [0x25F8]u8,
};

pub const Header = struct {
    magic: u32,
    unk_04: [0x8]u8,
    checksum: Checksum,
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

pub fn deserialize(reader: anytype, allocator: *Allocator) DeserializeError(@TypeOf(reader))!*Data {
    var data = try allocator.create(Data);
    errdefer allocator.destroy(data);

    inline for (comptime std.meta.fields(Data)) |field| {
        if (field.is_comptime) continue;
        try deserializeInto(field.field_type, &@field(data.*, field.name), reader);
    }

    return data;
}
