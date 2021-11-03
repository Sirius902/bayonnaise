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

    const save_data = try save_file.readToEndAlloc(allocator, save.pc_save_len);
    defer allocator.free(save_data);

    var stream = std.io.fixedBufferStream(save_data);

    const original = try save.Checksum.retrieve(&stream);
    const computed = try save.Checksum.compute(&stream);

    std.log.info("original: low sum = {x:0>8}, high sum = {x:0>8}, xor sum = {x:0>8}", .{ original.low, original.high, original.xor });
    std.log.info("computed: low sum = {x:0>8}, high sum = {x:0>8}, xor sum = {x:0>8}", .{ computed.low, computed.high, computed.xor });
}
