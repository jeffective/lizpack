const std = @import("std");

const spec = @import("specification.zig");

pub const MessagePackType = union(enum) {
    positive_fixint: u7,
    fixmap: []const MapItem,
    fixarray: []const MessagePackType,
    fixstr: []const u8,
    nil: void,
    bool: bool,
    bin_8: []const u8,
    bin_16: []const u8,
    bin_32: []const u8,
    ext_8: Ext8,
    ext_16: Ext16,
    ext_32: Ext32,
    float_32: f32,
    float_64: f64,
    uint_8: u8,
    uint_16: u16,
    uint_32: u32,
    uint_64: u64,
    int_8: i8,
    int_16: i16,
    int_32: i32,
    int_64: i64,
    fixext_1: Fixext1,
    fixext_2: Fixext2,
    fixext_4: Fixext4,
    fixext_8: Fixext8,
    fixext_16: Fixext16,
    str_8: []const u8,
    str_16: []const u8,
    str_32: []const u8,
    array_16: []const MessagePackType,
    array_32: []const MessagePackType,
    map_16: []const MapItem,
    map_32: []const MapItem,
    negative_fixint: i6,

    pub const MapItem = struct {
        key: MessagePackType,
        value: MessagePackType,
    };

    pub const Fixext1 = struct {
        type: i8,
        data: [1]u8,
    };
    pub const Fixext2 = struct {
        type: i8,
        data: [2]u8,
    };
    pub const Fixext4 = struct {
        type: i8,
        data: [4]u8,
    };
    pub const Fixext8 = struct {
        type: i8,
        data: [8]u8,
    };
    pub const Fixext16 = struct {
        type: i8,
        data: [16]u8,
    };
    pub const Ext8 = struct {
        type: i8,
        data: []u8,
    };
    pub const Ext16 = struct {
        type: i8,
        data: []u8,
    };
    pub const Ext32 = struct {
        type: i8,
        data: []u8,
    };
};

pub fn encodeAlloc(allocator: std.mem.Allocator, value: MessagePackType) error{ OutOfMemory, SliceLenTooLarge, InvalidNegativeFixInt }![]u8 {
    var bytes = std.ArrayList(u8).init(allocator);
    defer bytes.deinit();
    try encodeRecursive(value, bytes.writer());
    const slice = try bytes.toOwnedSlice();
    errdefer unreachable;
    return slice;
}

/// Call deinit() on this to free it.
pub fn Decoded(comptime T: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        value: T,
        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub fn decodeAlloc(allocator: std.mem.Allocator, in: []const u8) error{ OutOfMemory, Invalid }!Decoded(MessagePackType) {
    var fbs = std.io.fixedBufferStream(in);
    const arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = .init(allocator);
    errdefer arena.deinit();
    const res = decodeRecursive(arena.allocator(), fbs.reader()) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return error.Invalid,
        error.EndOfStream => return error.Invalid,
    };
    if (fbs.pos != fbs.buffer.len) return error.Invalid;
    return Decoded(MessagePackType){ .arena = arena, .value = res };
}

pub fn decodeRecursive(allocator: std.mem.Allocator, reader: anytype) !MessagePackType {
    const format = spec.Format.decode(try reader.readByte());
    switch (format) {
        .never_used => return error.Invalid,
        .positive_fixint => |fmt| return MessagePackType{ .positive_fixint = fmt.value },
        .negative_fixint => |fmt| return MessagePackType{ .negative_fixint = @intCast(fmt.value) },
        .true => return MessagePackType{ .bool = true },
        .false => return MessagePackType{ .bool = false },
        .nil => return MessagePackType{ .nil = {} },
        .uint_8 => return MessagePackType{ .uint_8 = try reader.readInt(u8, .big) },
        .uint_16 => return MessagePackType{ .uint_16 = try reader.readInt(u16, .big) },
        .uint_32 => return MessagePackType{ .uint_32 = try reader.readInt(u32, .big) },
        .uint_64 => return MessagePackType{ .uint_64 = try reader.readInt(u64, .big) },
        .int_8 => return MessagePackType{ .int_8 = try reader.readInt(i8, .big) },
        .int_16 => return MessagePackType{ .int_16 = try reader.readInt(i16, .big) },
        .int_32 => return MessagePackType{ .int_32 = try reader.readInt(i32, .big) },
        .int_64 => return MessagePackType{ .int_64 = try reader.readInt(i64, .big) },
        .float_32 => return MessagePackType{ .float_32 = @bitCast(try reader.readInt(u32, .big)) },
        .float_64 => return MessagePackType{ .float_64 = @bitCast(try reader.readInt(u64, .big)) },
        .fixext_1 => return MessagePackType{
            .fixext_1 = .{
                .type = try reader.readInt(i8, .big),
                .data = blk: {
                    var bytes: [1]u8 = undefined;
                    try reader.readNoEof(&bytes);
                    break :blk bytes;
                },
            },
        },
        .fixext_2 => return MessagePackType{
            .fixext_2 = .{
                .type = try reader.readInt(i8, .big),
                .data = blk: {
                    var bytes: [2]u8 = undefined;
                    try reader.readNoEof(&bytes);
                    break :blk bytes;
                },
            },
        },
        .fixext_4 => return MessagePackType{
            .fixext_4 = .{
                .type = try reader.readInt(i8, .big),
                .data = blk: {
                    var bytes: [4]u8 = undefined;
                    try reader.readNoEof(&bytes);
                    break :blk bytes;
                },
            },
        },
        .fixext_8 => return MessagePackType{
            .fixext_8 = .{
                .type = try reader.readInt(i8, .big),
                .data = blk: {
                    var bytes: [8]u8 = undefined;
                    try reader.readNoEof(&bytes);
                    break :blk bytes;
                },
            },
        },
        .fixext_16 => return MessagePackType{
            .fixext_16 = .{
                .type = try reader.readInt(i8, .big),
                .data = blk: {
                    var bytes: [16]u8 = undefined;
                    try reader.readNoEof(&bytes);
                    break :blk bytes;
                },
            },
        },
        .fixmap => |fmt| {
            const res = try allocator.alloc(MessagePackType.MapItem, fmt.n_elements);
            errdefer allocator.free(res);
            for (res) |*item| {
                item.key = try decodeRecursive(allocator, reader);
                item.value = try decodeRecursive(allocator, reader);
            }
            return MessagePackType{ .fixmap = res };
        },
        .fixarray => |fmt| {
            const res = try allocator.alloc(MessagePackType, fmt.len);
            errdefer allocator.free(res);
            for (res) |*item| {
                item.* = try decodeRecursive(allocator, reader);
            }
            return MessagePackType{ .fixarray = res };
        },
        .fixstr => |fmt| {
            const res = try allocator.alloc(u8, fmt.len);
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .fixstr = res };
        },
        .bin_8 => {
            const res = try allocator.alloc(u8, try reader.readInt(u8, .big));
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .bin_8 = res };
        },
        .bin_16 => {
            const res = try allocator.alloc(u8, try reader.readInt(u16, .big));
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .bin_16 = res };
        },
        .bin_32 => {
            const res = try allocator.alloc(u8, try reader.readInt(u32, .big));
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .bin_32 = res };
        },
        .str_8 => {
            const res = try allocator.alloc(u8, try reader.readInt(u8, .big));
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .str_8 = res };
        },
        .str_16 => {
            const res = try allocator.alloc(u8, try reader.readInt(u16, .big));
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .str_16 = res };
        },
        .str_32 => {
            const res = try allocator.alloc(u8, try reader.readInt(u32, .big));
            errdefer allocator.free(res);
            try reader.readNoEof(res);
            return MessagePackType{ .str_32 = res };
        },
        .map_16 => {
            const res = try allocator.alloc(MessagePackType.MapItem, try reader.readInt(u16, .big));
            errdefer allocator.free(res);
            for (res) |*item| {
                item.key = try decodeRecursive(allocator, reader);
                item.value = try decodeRecursive(allocator, reader);
            }
            return MessagePackType{ .map_16 = res };
        },
        .map_32 => {
            const res = try allocator.alloc(MessagePackType.MapItem, try reader.readInt(u32, .big));
            errdefer allocator.free(res);
            for (res) |*item| {
                item.key = try decodeRecursive(allocator, reader);
                item.value = try decodeRecursive(allocator, reader);
            }
            return MessagePackType{ .map_32 = res };
        },
        .array_16 => {
            const res = try allocator.alloc(MessagePackType, try reader.readInt(u16, .big));
            errdefer allocator.free(res);
            for (res) |*item| {
                item.* = try decodeRecursive(allocator, reader);
            }
            return MessagePackType{ .array_16 = res };
        },
        .array_32 => {
            const res = try allocator.alloc(MessagePackType, try reader.readInt(u32, .big));
            errdefer allocator.free(res);
            for (res) |*item| {
                item.* = try decodeRecursive(allocator, reader);
            }
            return MessagePackType{ .array_32 = res };
        },
        .ext_8 => {
            const data = try allocator.alloc(u8, try reader.readInt(u8, .big));
            errdefer allocator.free(data);
            const typ = try reader.readInt(i8, .big);
            try reader.readNoEof(data);
            return MessagePackType{ .ext_8 = .{ .type = typ, .data = data } };
        },
        .ext_16 => {
            const data = try allocator.alloc(u8, try reader.readInt(u16, .big));
            errdefer allocator.free(data);
            const typ = try reader.readInt(i8, .big);
            try reader.readNoEof(data);
            return MessagePackType{ .ext_16 = .{ .type = typ, .data = data } };
        },
        .ext_32 => {
            const data = try allocator.alloc(u8, try reader.readInt(u32, .big));
            errdefer allocator.free(data);
            const typ = try reader.readInt(i8, .big);
            try reader.readNoEof(data);
            return MessagePackType{ .ext_32 = .{ .type = typ, .data = data } };
        },
    }
}

pub fn encodeRecursive(value: MessagePackType, writer: anytype) !void {
    // check slice len or value
    switch (value) {
        .fixmap => |payload| if (payload.len > std.math.maxInt(u4)) return error.SliceLenTooLarge,
        .fixarray => |payload| if (payload.len > std.math.maxInt(u4)) return error.SliceLenTooLarge,
        .fixstr => |payload| if (payload.len > std.math.maxInt(u5)) return error.SliceLenTooLarge,
        .bin_8, .str_8 => |payload| if (payload.len > std.math.maxInt(u8)) return error.SliceLenTooLarge,
        .bin_16, .str_16 => |payload| if (payload.len > std.math.maxInt(u16)) return error.SliceLenTooLarge,
        .bin_32, .str_32 => |payload| if (payload.len > std.math.maxInt(u32)) return error.SliceLenTooLarge,
        .array_16 => |payload| if (payload.len > std.math.maxInt(u16)) return error.SliceLenTooLarge,
        .array_32 => |payload| if (payload.len > std.math.maxInt(u32)) return error.SliceLenTooLarge,
        .map_16 => |payload| if (payload.len > std.math.maxInt(u16)) return error.SliceLenTooLarge,
        .map_32 => |payload| if (payload.len > std.math.maxInt(u32)) return error.SliceLenTooLarge,
        .ext_8 => |payload| if (payload.data.len > std.math.maxInt(u8)) return error.SliceLenTooLarge,
        .ext_16 => |payload| if (payload.data.len > std.math.maxInt(u16)) return error.SliceLenTooLarge,
        .ext_32 => |payload| if (payload.data.len > std.math.maxInt(u32)) return error.SliceLenTooLarge,
        .negative_fixint => |payload| if (payload >= 0) return error.InvalidNegativeFixInt,
        .positive_fixint,
        .nil,
        .bool,
        .fixext_1,
        .fixext_16,
        .fixext_2,
        .fixext_4,
        .fixext_8,
        .float_32,
        .float_64,
        .int_16,
        .int_32,
        .int_64,
        .int_8,
        .uint_16,
        .uint_32,
        .uint_64,
        .uint_8,
        => {},
    }
    const format: spec.Format = switch (value) {
        .positive_fixint => |payload| .{ .positive_fixint = .{ .value = payload } },
        .negative_fixint => |payload| .{ .negative_fixint = .{ .value = payload } },
        .fixmap => |payload| .{ .fixmap = .{ .n_elements = @intCast(payload.len) } },
        .fixarray => |payload| .{ .fixarray = .{ .len = @intCast(payload.len) } },
        .fixstr => |payload| .{ .fixstr = .{ .len = @intCast(payload.len) } },
        .bool => |payload| switch (payload) {
            true => .{ .true = {} },
            false => .{ .false = {} },
        },
        inline else => |payload, tag| blk: {
            _ = payload;
            break :blk @unionInit(spec.Format, @tagName(tag), {});
        },
    };
    try writer.writeByte(format.encode());

    switch (value) {
        .positive_fixint,
        .negative_fixint,
        .bool,
        .nil,
        => {},
        .fixmap => |payload| for (payload) |item| {
            try encodeRecursive(item.key, writer);
            try encodeRecursive(item.value, writer);
        },
        .fixarray => |payload| for (payload) |item| {
            try encodeRecursive(item, writer);
        },
        .fixstr => |payload| try writer.writeAll(payload),

        .bin_8, .str_8 => |payload| {
            try writer.writeInt(u8, @intCast(payload.len), .big);
            try writer.writeAll(payload);
        },
        .bin_16, .str_16 => |payload| {
            try writer.writeInt(u16, @intCast(payload.len), .big);
            try writer.writeAll(payload);
        },
        .bin_32, .str_32 => |payload| {
            try writer.writeInt(u32, @intCast(payload.len), .big);
            try writer.writeAll(payload);
        },
        .ext_8 => |payload| {
            try writer.writeInt(u8, @intCast(payload.data.len), .big);
            try writer.writeInt(i8, @intCast(payload.type), .big);
            try writer.writeAll(payload.data);
        },
        .ext_16 => |payload| {
            try writer.writeInt(u16, @intCast(payload.data.len), .big);
            try writer.writeInt(i8, @intCast(payload.type), .big);
            try writer.writeAll(payload.data);
        },
        .ext_32 => |payload| {
            try writer.writeInt(u32, @intCast(payload.data.len), .big);
            try writer.writeInt(i8, @intCast(payload.type), .big);
            try writer.writeAll(payload.data);
        },
        .float_32 => |payload| try writer.writeInt(u32, @bitCast(payload), .big),
        .float_64 => |payload| try writer.writeInt(u64, @bitCast(payload), .big),
        .uint_8 => |payload| try writer.writeInt(u8, payload, .big),
        .uint_16 => |payload| try writer.writeInt(u16, payload, .big),
        .uint_32 => |payload| try writer.writeInt(u32, payload, .big),
        .uint_64 => |payload| try writer.writeInt(u64, payload, .big),
        .int_8 => |payload| try writer.writeInt(i8, payload, .big),
        .int_16 => |payload| try writer.writeInt(i16, payload, .big),
        .int_32 => |payload| try writer.writeInt(i32, payload, .big),
        .int_64 => |payload| try writer.writeInt(i64, payload, .big),
        .fixext_1 => |payload| {
            try writer.writeInt(i8, payload.type, .big);
            try writer.writeAll(&payload.data);
        },
        .fixext_2 => |payload| {
            try writer.writeInt(i8, payload.type, .big);
            try writer.writeAll(&payload.data);
        },
        .fixext_4 => |payload| {
            try writer.writeInt(i8, payload.type, .big);
            try writer.writeAll(&payload.data);
        },
        .fixext_8 => |payload| {
            try writer.writeInt(i8, payload.type, .big);
            try writer.writeAll(&payload.data);
        },
        .fixext_16 => |payload| {
            try writer.writeInt(i8, payload.type, .big);
            try writer.writeAll(&payload.data);
        },
        .array_16 => |payload| {
            try writer.writeInt(u16, @intCast(payload.len), .big);
            for (payload) |item| {
                try encodeRecursive(item, writer);
            }
        },
        .array_32 => |payload| {
            try writer.writeInt(u32, @intCast(payload.len), .big);
            for (payload) |item| {
                try encodeRecursive(item, writer);
            }
        },
        .map_16 => |payload| {
            try writer.writeInt(u16, @intCast(payload.len), .big);
            for (payload) |item| {
                try encodeRecursive(item.key, writer);
                try encodeRecursive(item.value, writer);
            }
        },
        .map_32 => |payload| {
            try writer.writeInt(u32, @intCast(payload.len), .big);
            for (payload) |item| {
                try encodeRecursive(item.key, writer);
                try encodeRecursive(item.value, writer);
            }
        },
    }
}

test "encode positive fix int" {
    const expected: []const u8 = &.{0};
    const actual: MessagePackType = .{ .positive_fixint = 0 };
    const encoded = try encodeAlloc(std.testing.allocator, actual);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, expected, encoded);
}

test "encode negative fix int" {
    const expected: []const u8 = &.{@bitCast(@as(i8, -15))};
    const actual: MessagePackType = .{ .negative_fixint = -15 };
    const encoded = try encodeAlloc(std.testing.allocator, actual);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, expected, encoded);
}

test "decode negative fix int" {
    const raw: []const u8 = &.{@bitCast(@as(i8, -15))};
    const expected: MessagePackType = .{ .negative_fixint = -15 };
    const decoded = try decodeAlloc(std.testing.allocator, raw);
    defer decoded.deinit();
    try std.testing.expectEqualDeep(expected, decoded.value);
}

test {
    _ = std.testing.refAllDecls(@This());
}
