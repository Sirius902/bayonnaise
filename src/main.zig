const std = @import("std");
const save = @import("save.zig");
const s = @import("serialize.zig");

comptime {
    std.testing.refAllDecls(@This());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
    const save_data = try s.deserialize(save.FileData, reader, allocator);
    defer allocator.destroy(save_data);

    std.log.info("magic = {x:0>8},\tchecksums = {{ low = {x:0>8}, high = {x:0>8}, xor = {x:0>8} }}", .{
        save_data.header.magic,
        save_data.header.checksums.low,
        save_data.header.checksums.high,
        save_data.header.checksums.xor,
    });

    const computed = try checksum_reader.finalize();
    std.log.info("calculated:\tchecksums = {{ low = {x:0>8}, high = {x:0>8}, xor = {x:0>8} }}", .{
        computed.low,
        computed.high,
        computed.xor,
    });

    std.log.info("chapter: {}", .{save_data.unk_30.chapter});
    std.log.info("difficulty: {}", .{save_data.unk_30.difficulty});

    std.log.info("play time: {:0>2}:{:0>2}:{:0>2} | frames: {}", .{
        save_data.unk_30.play_time / (60 * 60 * 60),
        (save_data.unk_30.play_time / (60 * 60)) % 60,
        (save_data.unk_30.play_time / 60) % 60,
        save_data.unk_30.play_time,
    });
    std.log.info("halos: {}", .{save_data.unk_EEB0.halos});
    std.log.info("chapter clears: {}", .{save_data.unk_30.chapter_clears});

    std.log.info("====<Normal> Prologue Stats====", .{});
    const ch = &save_data.unk_30.chapter_stats[2][1];
    std.log.info("info: {x:0>2}", .{ch.info});
    std.log.info("time: {:0>2}:{:0>2}:{:0>2}.{:0>2} | frames: {}", .{
        ch.overall.time / (60 * 60 * 60),
        (ch.overall.time / (60 * 60)) % 60,
        (ch.overall.time / 60) % 60,
        ((ch.overall.time * 100) / 60) % 100,
        ch.overall.time,
    });
    std.log.info("combo: {}", .{ch.overall.combo});
    std.log.info("damage: {}", .{ch.overall.damage});
    for (ch.verses[1..3]) |verse, i| {
        std.log.info("=========Verse {} Start=========", .{i + 1});
        std.log.info("time: {:0>2}:{:0>2}:{:0>2}.{:0>2} | frames: {}", .{
            verse.time / (60 * 60 * 60),
            (verse.time / (60 * 60)) % 60,
            (verse.time / 60) % 60,
            ((verse.time * 10) / 6) % 100,
            verse.time,
        });
        std.log.info("combo: {}", .{verse.combo});
        std.log.info("damage: {}", .{verse.damage});
        std.log.info("==========Verse {} End==========", .{i + 1});
    }
    std.log.info("=====<Normal> Prologue End=====", .{});

    const characters = [_][]const u8{ "Bayonetta", "Jeanne", "Zero" };
    if (save_data.unk_EEB0.character < characters.len) {
        std.log.info("character: {s}", .{characters[save_data.unk_EEB0.character]});
    } else {
        std.log.info("character: Invalid = 0x{x:0>8}", .{save_data.unk_EEB0.character});
    }
}
