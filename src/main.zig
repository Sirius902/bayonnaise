const std = @import("std");
const save = @import("save.zig");

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

    if ((try save_file.stat()).size != save.pc_save_len) {
        std.log.err("save file has incorrect size", .{});
        return;
    }

    var checksum_reader = save.checksumReader(std.io.bufferedReader(save_file.reader()).reader());
    const reader = checksum_reader.reader();
    const save_data = try save.deserialize(reader, allocator);
    defer allocator.destroy(save_data);

    std.log.info("magic = {x:0>8},\tchecksums = {{ low = {x:0>8}, high = {x:0>8}, xor = {x:0>8} }}", .{
        save_data.header.magic,
        save_data.header.checksum.low,
        save_data.header.checksum.high,
        save_data.header.checksum.xor,
    });

    const computed = try checksum_reader.finalize();
    std.log.info("calculated:\tchecksums = {{ low = {x:0>8}, high = {x:0>8}, xor = {x:0>8} }}", .{
        computed.low,
        computed.high,
        computed.xor,
    });
}
