const std = @import("std");

pub fn streamedSize(comptime T: type) usize {
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

pub fn streamedOffset(comptime T: type, comptime field_name: []const u8) usize {
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

pub fn DeserializeError(comptime ReaderType: type) type {
    return ReaderType.Error || error{EndOfStream} || std.mem.Allocator.Error;
}

fn deserializeInto(comptime T: type, t: *T, reader: anytype) !void {
    switch (@typeInfo(T)) {
        .Void => {},
        .Bool => t.* = try reader.readByte() != 0,
        .Int => t.* = try reader.readInt(T, std.builtin.Endian.Little),
        .Float => |F| t.* = @bitCast(T, try reader.readInt(
            std.meta.Int(.signed, F.bits),
            std.builtin.Endian.Little,
        )),
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

pub fn deserialize(comptime T: type, reader: anytype, allocator: std.mem.Allocator) DeserializeError(@TypeOf(reader))!*T {
    var data = try allocator.create(T);
    errdefer allocator.destroy(data);

    inline for (comptime std.meta.fields(T)) |field| {
        if (field.is_comptime) continue;
        try deserializeInto(field.field_type, &@field(data.*, field.name), reader);
    }

    return data;
}
