const std = @import("std");

pub const pc_save_len = 0x11550;

pub const Data = struct {
    magic: u32,
    unk_04: [0x8]u8,
    checksum: Checksum,
    unk_20: [0x11538]u8,
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
