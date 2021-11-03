const std = @import("std");

const pc_save_len = 0x11550;

const Checksums = struct {
    low_sum: u32,
    high_sum: u32,
    xor_sum: u32,

    pub fn retrieve(stream: anytype) !Checksums {
        try stream.seekTo(0xC);
        const reader = stream.reader();

        return Checksums{
            .low_sum = try reader.readIntLittle(u32),
            .high_sum = try reader.readIntLittle(u32),
            .xor_sum = try reader.readIntLittle(u32),
        };
    }

    pub fn compute(stream: anytype) !Checksums {
        try stream.seekTo(0x20);
        const reader = stream.reader();

        var low_sum: u32 = 0;
        var high_sum: u32 = 0;
        var xor_sum: u32 = 0;

        while (true) {
            const word = reader.readIntLittle(u32) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => return err,
                }
            };

            low_sum += @truncate(u16, word);
            high_sum += @truncate(u16, word >> @bitSizeOf(u16));
            xor_sum ^= word;
        }

        return Checksums{
            .low_sum = low_sum,
            .high_sum = high_sum,
            .xor_sum = xor_sum,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("missing save file argument", .{});
        return;
    }

    const save_file = std.fs.cwd().openFile(args[1], .{}) catch |err| {
        std.log.err("{}: failed to open save file", .{err});
        return;
    };
    defer save_file.close();

    if ((try save_file.stat()).size != pc_save_len) {
        std.log.err("save file has incorrect size", .{});
        return;
    }

    const save_data = try save_file.readToEndAlloc(allocator, pc_save_len);
    defer allocator.free(save_data);

    var stream = std.io.fixedBufferStream(save_data);

    const original = try Checksums.retrieve(&stream);
    const computed = try Checksums.compute(&stream);

    std.log.info("original: low sum = {x:0>8}, high sum = {x:0>8}, xor sum = {x:0>8}", .{ original.low_sum, original.high_sum, original.xor_sum });
    std.log.info("computed: low sum = {x:0>8}, high sum = {x:0>8}, xor sum = {x:0>8}", .{ computed.low_sum, computed.high_sum, computed.xor_sum });
}
