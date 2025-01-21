const std = @import("std");

const Spec = @import("Specification.zig");

pub const MessagePackType = union(enum) {
    integer: i65,
    nil: void,
    boolean: bool,
    float: f64,
    raw: []const u8,
    array: []MessagePackType,

    pub const MapItem = struct {
        key: MessagePackType,
        value: MessagePackType,
    };
};

fn encodeAlloc(allocator: std.mem.Allocator, value: MessagePackType) ![]u8 {
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
    const res = decodeRecursive(fbs.reader(), arena.allocator()) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Invalid => return error.Invalid,
        error.EndOfStream => return error.Invalid,
    };
    if (fbs.pos != fbs.buffer.len) return error.Invalid;
    return Decoded(MessagePackType){ .arena = arena, .value = res };
}

fn decodeRecursive(reader: anytype, allocator: std.mem.Allocator) error{ OutOfMemory, Invalid, EndOfStream }!MessagePackType {
    _ = allocator;
    const format = Spec.Format.decode(try reader.readByte());
    switch (format) {
        .positive_fixint => |fmt| return MessagePackType{ .integer = fmt.value },
        .negative_fixint => |fmt| return MessagePackType{ .integer = fmt.value },
        .uint_8 => return MessagePackType{ .integer = try reader.readInt(u8, .big) },
        .uint_16 => return MessagePackType{ .integer = try reader.readInt(u16, .big) },
        .uint_32 => return MessagePackType{ .integer = try reader.readInt(u32, .big) },
        .uint_64 => return MessagePackType{ .integer = try reader.readInt(u64, .big) },
        .int_8 => return MessagePackType{ .integer = try reader.readInt(i8, .big) },
        .int_16 => return MessagePackType{ .integer = try reader.readInt(i16, .big) },
        .int_32 => return MessagePackType{ .integer = try reader.readInt(i32, .big) },
        .int_64 => return MessagePackType{ .integer = try reader.readInt(i64, .big) },
        else => unreachable, // TODO
    }
}

fn encodeRecursive(value: MessagePackType, writer: anytype) !void {
    switch (value) {
        .integer => try encodeInteger(value.integer, writer),
        else => unreachable, // TODO
    }
}

fn encodeInteger(value: i65, writer: anytype) !void {
    const format: Spec.Format = switch (value) {
        std.math.minInt(i64)...std.math.minInt(i32) - 1 => .{ .int_64 = {} },
        std.math.minInt(i32)...std.math.minInt(i16) - 1 => .{ .int_32 = {} },
        std.math.minInt(i16)...std.math.minInt(i8) - 1 => .{ .int_16 = {} },
        std.math.minInt(i8)...-33 => .{ .int_8 = {} },
        -32...-1 => .{ .negative_fixint = .{ .value = @intCast(value) } },
        0...std.math.maxInt(u7) => .{ .positive_fixint = .{ .value = @intCast(value) } },
        std.math.maxInt(u7) + 1...std.math.maxInt(u8) => .{ .uint_8 = {} },
        std.math.maxInt(u8) + 1...std.math.maxInt(u16) => .{ .uint_16 = {} },
        std.math.maxInt(u16) + 1...std.math.maxInt(u32) => .{ .uint_32 = {} },
        std.math.maxInt(u32) + 1...std.math.maxInt(u64) => .{ .uint_64 = {} },
        else => unreachable,
    };
    try writer.writeByte(format.encode());
    switch (format) {
        .positive_fixint, .negative_fixint => {},
        .uint_8 => try writer.writeInt(u8, @intCast(value), .big),
        .uint_16 => try writer.writeInt(u16, @intCast(value), .big),
        .uint_32 => try writer.writeInt(u32, @intCast(value), .big),
        .uint_64 => try writer.writeInt(u64, @intCast(value), .big),
        .int_8 => try writer.writeInt(i8, @intCast(value), .big),
        .int_16 => try writer.writeInt(i16, @intCast(value), .big),
        .int_32 => try writer.writeInt(i32, @intCast(value), .big),
        .int_64 => try writer.writeInt(i64, @intCast(value), .big),
        else => unreachable,
    }
}

test {
    _ = std.testing.refAllDecls(@This());
}

test "all the integers" {
    inline for (0..64) |bits| {
        const signs = &.{ .signed, .unsigned };
        inline for (signs) |sign| {
            const int: type = @Type(.{ .int = .{ .bits = bits, .signedness = sign } });
            if (bits < 22) {
                for (0..std.math.maxInt(int) + 1) |value| {
                    var buffer: [1000]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
                    const allocator = fba.allocator();
                    const expected = MessagePackType{ .integer = @intCast(value) };
                    const encoded: []const u8 = try encodeAlloc(allocator, expected);
                    defer allocator.free(encoded);
                    const decoded = try decodeAlloc(allocator, encoded);
                    defer decoded.deinit();
                    try std.testing.expectEqual(expected, decoded.value);
                }
            } else {
                for (0..1000) |_| {
                    var buffer: [1000]u8 = undefined;
                    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
                    const allocator = fba.allocator();
                    const expected = MessagePackType{ .integer = std.crypto.random.int(int) };
                    const encoded: []const u8 = try encodeAlloc(allocator, expected);
                    defer allocator.free(encoded);
                    const decoded = try decodeAlloc(allocator, encoded);
                    defer decoded.deinit();
                    try std.testing.expectEqual(expected, decoded.value);
                }
            }
        }
    }
}
