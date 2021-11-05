const std = @import("std");
const Allocator = std.mem.Allocator;

pub const pc_save_len = 0x11550;

pub const Data = struct {
    magic: u32,
    unk_04: [0x8]u8,
    checksum: Checksum,
    unk_18: [0x11538]u8,
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

const ChecksumState = struct {
    checksum: Checksum,
    state: [4]u8,
    index: usize,

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
};

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
            for (t) |*v| {
                try deserializeInto(A.child, v, reader);
            }
        },
        else => @compileError("unsupported type: " ++ @typeName(T)),
    }
}

pub fn deserialize(reader: anytype, allocator: *Allocator) DeserializeError(@TypeOf(reader))!*Data {
    var data = try allocator.create(Data);
    errdefer allocator.destroy(data);

    inline for (std.meta.fields(Data)) |field| {
        if (field.is_comptime) continue;

        try deserializeInto(field.field_type, &@field(data.*, field.name), reader);
    }

    return data;
}
