const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const cast = std.math.cast;
const myType = std.builtin.Type;

pub const Spec = @import("Specification.zig");

pub fn encode(value: anytype, out: []u8) !void {
    var fbs = std.io.fixedBufferStream(out);
    const writer = fbs.writer();
    switch (@typeInfo(@TypeOf(value))) {
        .void => unreachable,
        .null => try writer.writeByte(0xc0),
        else => @compileError("not implemented"),
    }
}

pub fn decode(comptime T: type, in: []const u8) !T {
    var fbs = std.io.fixedBufferStream(in);
    const reader = fbs.reader();

    switch (@typeInfo(T)) {
        .void => unreachable,
        .bool => return try decodeBool(try reader.readByte()),
        .int => return try decodeInt(T, in),
        .float => return try decodeFloat(T, in),
        else => @compileError("not implemented"),
    }
    unreachable;
}

fn decodeBool(in: u8) error{Invalid}!bool {
    switch (Spec.Format.decode(in)) {
        .true => return true,
        .false => return false,
        else => return error.Invalid,
    }
    unreachable;
}

test "decode bool" {
    try std.testing.expectEqual(true, decode(bool, &.{0xc3}));
    try std.testing.expectEqual(false, decode(bool, &.{0xc2}));
    try std.testing.expectError(error.Invalid, decode(bool, &.{0xe3}));
}

fn decodeInt(comptime T: type, in: []const u8) error{ Invalid, EndOfStream }!T {
    var fbs = std.io.fixedBufferStream(in);
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());
    switch (format) {
        .positive_fixint => |val| return std.math.cast(T, val.value) orelse return error.Invalid,
        .uint_8 => return cast(T, try reader.readInt(u8, .big)) orelse return error.Invalid,
        .uint_16 => return cast(T, try reader.readInt(u16, .big)) orelse return error.Invalid,
        .uint_32 => return cast(T, try reader.readInt(u32, .big)) orelse return error.Invalid,
        .uint_64 => return cast(T, try reader.readInt(u64, .big)) orelse return error.Invalid,
        .int_8 => return cast(T, try reader.readInt(i8, .big)) orelse return error.Invalid,
        .int_16 => return cast(T, try reader.readInt(i16, .big)) orelse return error.Invalid,
        .int_32 => return cast(T, try reader.readInt(i32, .big)) orelse return error.Invalid,
        .int_64 => return cast(T, try reader.readInt(u8, .big)) orelse return error.Invalid,
        .negative_fixint => |val| return std.math.cast(T, -@as(i6, val.negative_value)) orelse return error.Invalid,
        else => return error.Invalid,
    }
    unreachable;
}

test "decode int" {
    try std.testing.expectEqual(@as(u5, 0), decode(u5, &.{ 0xcc, 0x00 }));
    try std.testing.expectEqual(@as(u5, 3), decode(u5, &.{ 0xcc, 0x03 }));
    try std.testing.expectEqual(@as(u5, 0), decode(u5, &.{0x00}));
    try std.testing.expectEqual(@as(u5, 3), decode(u5, &.{0x03}));
    try std.testing.expectEqual(@as(i5, 0), decode(i5, &.{0x00}));
    try std.testing.expectEqual(@as(i5, -3), decode(i5, &.{0b11100011}));
    try std.testing.expectError(error.Invalid, decode(i5, &.{0xb3}));
}

fn decodeFloat(comptime T: type, in: []const u8) error{ Invalid, EndOfStream }!T {
    var fbs = std.io.fixedBufferStream(in);
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());
    if (@typeInfo(T).float.bits == 32) {
        switch (format) {
            .float_32 => return @bitCast(try reader.readInt(u32, .big)),
            else => return error.Invalid,
        }
    } else if (@typeInfo(T).float.bits == 64) {
        switch (format) {
            .float_64 => return @bitCast(try reader.readInt(u64, .big)),
            else => return error.Invalid,
        }
    } else @compileError("Unsupported float type: " ++ @typeName(T));

    unreachable;
}

test "decode float" {
    try std.testing.expectEqual(@as(f32, 1.23), try decode(f32, &.{ 0xca, 0x3f, 0x9d, 0x70, 0xa4 }));
    try std.testing.expectEqual(@as(f64, 1.23), try decode(f64, &.{ 0xcb, 0x3f, 0xf3, 0xae, 0x14, 0x7a, 0xe1, 0x47, 0xae }));
    // TODO: test decode float error
}

test {
    _ = std.testing.refAllDecls(@This());
}
