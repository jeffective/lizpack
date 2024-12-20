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
    const res = try decodeFbs(T, &fbs);
    if (fbs.pos != fbs.buffer.len) return error.Invalid;
    return res;
}

test "byte stream too long returns error" {
    try std.testing.expectError(error.Invalid, decode(bool, &.{ 0xc3, 0x00 }));
}

fn decodeFbs(comptime T: type, fbs: *FBS) !T {
    switch (@typeInfo(T)) {
        .void => unreachable,
        .bool => return try decodeBool(fbs),
        .int => return try decodeInt(T, fbs),
        .float => return try decodeFloat(T, fbs),
        .array => return try decodeArray(T, fbs),
        .optional => return try decodeOptional(T, fbs),
        .vector => return try decodeVector(T, fbs),
        .@"struct" => return try decodeStruct(T, fbs),
        else => @compileError("type: " ++ @typeName(T) ++ " not supported."),
    }
    unreachable;
}

fn largestFieldNameLength(comptime T: type) comptime_int {
    const field_names = std.meta.fieldNames(T);
    if (field_names.len == 0) return 0;
    comptime var biggest_len = 0;
    for (field_names, 0..) |field_name, i| {
        if (i == 0) {
            biggest_len = field_name.len;
            continue;
        }
        if (field_name.len > biggest_len) {
            biggest_len = field_name.len;
        }
    }
    return biggest_len;
}

test "largest field name length" {
    const Foo = struct {
        bar: u8,
        bar2: u8,
    };
    try std.testing.expectEqual(4, largestFieldNameLength(Foo));
}

fn decodeStruct(comptime T: type, fbs: *FBS) !T {
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());
    const num_struct_fields = @typeInfo(T).@"struct".fields.len;

    switch (format) {
        .fixmap => |fix_map| if (fix_map.n_elements != num_struct_fields) return error.Invalid,
        .map_16 => if (try reader.readInt(u16, .big) != num_struct_fields) return error.Invalid,
        .map_32 => if (try reader.readInt(u32, .big) != num_struct_fields) return error.Invalid,
        else => return error.Invalid,
    }

    if (num_struct_fields == 0) return T{};

    assert(num_struct_fields > 0);

    var got_field: [num_struct_fields]bool = @splat(false);
    var res: T = undefined;
    // yes is this O(n2) ... i don't care.
    for (0..num_struct_fields) |_| {
        var field_name_buffer: [largestFieldNameLength(T)]u8 = undefined;
        const format_key = Spec.Format.decode(try reader.readByte());
        const name_len = switch (format_key) {
            .bin_8, .str_8 => try reader.readInt(u8, .big),
            .bin_16, .str_16 => try reader.readInt(u16, .big),
            .bin_32, .str_32 => try reader.readInt(u32, .big),
            .fixstr => |val| val.len,
            else => return error.Invalid,
        };
        if (name_len > largestFieldNameLength(T)) return error.Invalid;
        assert(name_len <= largestFieldNameLength(T));
        try reader.readNoEof(field_name_buffer[0..name_len]);
        inline for (comptime std.meta.fieldNames(T), 0..) |field_name, i| {
            if (std.mem.eql(u8, field_name, field_name_buffer[0..name_len])) {
                @field(res, field_name) = try decodeFbs(@FieldType(T, field_name), fbs);
                got_field[i] = true;
            }
        }
    }
    if (!std.mem.allEqual(bool, &got_field, true)) return error.Invalid;
    return res;
}

test "decode struct" {
    const Foo = struct {
        foo: u8 = 3,
        bar: u16 = 2,
    };
    const Foo2 = struct {
        bar: u8 = 2,
        foo: u16 = 3,
    };

    const bytes: []const u8 = &.{
        0b10000010, // map with two KV pairs
        0b10100011, // fix str 3 char
        'f',
        'o',
        'o',
        0x03,
        0b10100011, // fix str 3 char
        'b',
        'a',
        'r',
        0x02,
    };

    const bad_bytes: []const u8 = &.{
        0b10000010, // map with two KV pairs
        0b10100011, // fix str 3 char
        'f',
        'o',
        'o',
        0x03,
        0b10100011, // fix str 3 char
        'b',
        'a',
        'z',
        0x02,
    };

    try std.testing.expectEqualDeep(Foo{}, try decode(Foo, bytes));
    try std.testing.expectEqualDeep(Foo2{}, try decode(Foo2, bytes));
    try std.testing.expectError(error.Invalid, decode(Foo2, bad_bytes));
}

fn decodeOptional(comptime T: type, fbs: *FBS) !T {
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());

    const Child = @typeInfo(T).optional.child;
    switch (format) {
        .nil => return null,
        else => {
            // need to recover last byte we just consumed parsing the format.
            try fbs.seekBy(-1);
            return try decodeFbs(Child, fbs);
        },
    }
}

test "decode optional" {
    try std.testing.expectEqual(null, decode(?u8, &.{0xc0}));
    try std.testing.expectEqual(@as(u8, 1), decode(?u8, &.{0x01}));
}

fn decodeVector(comptime T: type, fbs: *FBS) error{ Invalid, EndOfStream }!T {
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());
    const expected_format_len = @typeInfo(T).vector.len;
    switch (format) {
        .fixarray => |fix_array| {
            if (fix_array.len != expected_format_len) {
                return error.Invalid;
            }
        },
        .array_16 => {
            if (try reader.readInt(u16, .big) != expected_format_len)
                return error.Invalid;
        },
        .array_32 => {
            if (try reader.readInt(u32, .big) != expected_format_len)
                return error.Invalid;
        },
        else => return error.Invalid,
    }
    var res: T = undefined;
    const Child = @typeInfo(T).vector.child;
    for (0..expected_format_len) |i| {
        res[i] = try decodeFbs(Child, fbs);
    }
    return res;
}

test "decode vector" {
    try std.testing.expectEqual(@Vector(3, bool){ true, false, true }, decode(@Vector(3, bool), &.{ 0b10010011, 0xc3, 0xc2, 0xc3 }));
}

fn decodeArray(comptime T: type, fbs: *FBS) error{ Invalid, EndOfStream }!T {
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());
    comptime var expected_format_len = @typeInfo(T).array.len;
    if (@typeInfo(T).array.sentinel) |_| expected_format_len += 1;
    switch (format) {
        .fixarray => |fix_array| {
            if (fix_array.len != expected_format_len) {
                return error.Invalid;
            }
        },
        .array_16 => {
            if (try reader.readInt(u16, .big) != expected_format_len)
                return error.Invalid;
        },
        .array_32 => {
            if (try reader.readInt(u32, .big) != expected_format_len)
                return error.Invalid;
        },
        else => return error.Invalid,
    }
    var res: T = undefined;
    const Child = @typeInfo(T).array.child;

    const decode_len = @typeInfo(T).array.len;
    for (0..decode_len) |i| {
        res[i] = try decodeFbs(Child, fbs);
    }
    if (@typeInfo(T).array.sentinel) |sentinel| {
        const sentinel_value: Child = @as(*const Child, @ptrCast(sentinel)).*;
        if (try decodeFbs(Child, fbs) != sentinel_value) return error.Invalid;
    }
    return res;
}

test "decode array" {
    try std.testing.expectEqual([3]bool{ true, false, true }, decode([3]bool, &.{ 0b10010011, 0xc3, 0xc2, 0xc3 }));
    try std.testing.expectEqual([4]u8{ 0, 1, 2, 3 }, decode([4]u8, &.{ 0b10010100, 0x00, 0x01, 0x02, 0x03 }));
}

test "decode array senstinel" {
    try std.testing.expectEqual([3:false]bool{ true, false, true }, decode([3:false]bool, &.{ 0b10010100, 0xc3, 0xc2, 0xc3, 0xc2 }));
}

const FBS = std.io.FixedBufferStream([]const u8);

fn decodeBool(fbs: *FBS) error{ Invalid, EndOfStream }!bool {
    const reader = fbs.reader();
    const format = Spec.Format.decode(try reader.readByte());
    switch (format) {
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

fn decodeInt(comptime T: type, fbs: *FBS) error{ Invalid, EndOfStream }!T {
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

fn decodeFloat(comptime T: type, fbs: *FBS) error{ Invalid, EndOfStream }!T {
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
}

test {
    _ = std.testing.refAllDecls(@This());
}
