const std = @import("std");
const assert = std.debug.assert;
const cast = std.math.cast;

pub const Spec = @import("Specification.zig");

pub fn encode(value: anytype, out: []u8) error{NoSpaceLeft}![]u8 {
    var fbs = std.io.fixedBufferStream(out);
    try encodeAny(value, fbs.writer(), fbs.seekableStream());
    return fbs.getWritten();
}

pub fn decode(comptime T: type, in: []const u8) error{Invalid}!T {
    var fbs = std.io.fixedBufferStream(in);
    const res = decodeAny(T, fbs.reader(), fbs.seekableStream()) catch return error.Invalid;
    if (fbs.pos != fbs.buffer.len) return error.Invalid;
    return res;
}

// pub fn decodeAlloc(comptime T: type, in: []const u8, allocator: std.mem.Allocator) error{ OutOfMemory, Invalid }!T {}

// pub fn decodeAnyAlloc(comptime T: type, in: []const u8, allocator: std.mem.Allocator) !T {
//     switch (@typeInfo(T)) {
//         .
//     }
// }

test "byte stream too long returns error" {
    try std.testing.expectError(error.Invalid, decode(bool, &.{ 0xc3, 0x00 }));
}

fn encodeAny(value: anytype, writer: anytype, seeker: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .bool => return try encodeBool(value, writer),
        .int => return try encodeInt(value, writer),
        .float => return try encodeFloat(value, writer),
        .array => return try encodeArray(value, writer, seeker),
        .optional => return try encodeOptional(value, writer, seeker),
        .vector => return try encodeVector(value, writer, seeker),
        .@"struct" => return try encodeStruct(value, writer, seeker),
        .@"enum" => return try encodeEnum(value, writer),
        .@"union" => return try encodeUnion(value, writer, seeker),
        else => @compileError("type: " ++ @typeName(T) ++ " not supported."),
    }
    unreachable;
}

fn encodeUnion(value: anytype, writer: anytype, seeker: anytype) !void {
    const union_payload = switch (value) {
        inline else => |payload| payload,
    };
    try encodeAny(union_payload, writer, seeker);
}

test "round trip union" {
    var out: [1000]u8 = undefined;
    const expected: union(enum) { foo: u8, bar: u16 } = .{ .foo = 3 };
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn encodeEnum(value: anytype, writer: anytype) !void {
    const TagInt = @typeInfo(@TypeOf(value)).@"enum".tag_type;
    const int: TagInt = @intFromEnum(value);
    try encodeInt(int, writer);
}

test "round trip enum" {
    var out: [1000]u8 = undefined;
    const expected: enum { foo, bar } = .foo;
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn encodeStruct(value: anytype, writer: anytype, seeker: anytype) !void {
    const num_struct_fields = @typeInfo(@TypeOf(value)).@"struct".fields.len;

    if (num_struct_fields == 0) return;

    assert(num_struct_fields > 0);

    const format: Spec.Format = switch (num_struct_fields) {
        0 => unreachable,
        1...std.math.maxInt(u4) => .{ .fixmap = .{ .n_elements = @intCast(num_struct_fields) } },
        std.math.maxInt(u4) + 1...std.math.maxInt(u16) => .{ .map_16 = {} },
        std.math.maxInt(u16) + 1...std.math.maxInt(u32) => .{ .map_32 = {} },
        else => @compileError("MessagePack only supports up to u32 len maps."),
    };

    try writer.writeByte(format.encode());

    inline for (comptime std.meta.fieldNames(@TypeOf(value))) |field_name| {
        const format_key: Spec.Format = switch (field_name.len) {
            0 => unreachable,
            1...std.math.maxInt(u5) => |len| .{ .fixstr = .{ .len = @intCast(len) } },
            std.math.maxInt(u5) + 1...std.math.maxInt(u8) => .{ .str_8 = {} },
            std.math.maxInt(u8) + 1...std.math.maxInt(u16) => .{ .str_16 = {} },
            std.math.maxInt(u16) + 1...std.math.maxInt(u32) => .{ .str_32 = {} },
            else => @compileError("Field name" ++ field_name ++ " too long"),
        };
        try writer.writeByte(format_key.encode());
        switch (format_key) {
            .fixstr => {},
            .str_8 => try writer.writeInt(u8, @intCast(field_name.len), .big),
            .str_16 => try writer.writeInt(u16, @intCast(field_name.len), .big),
            .str_32 => try writer.writeInt(u32, @intCast(field_name.len), .big),
            else => unreachable,
        }
        try writer.writeAll(field_name);
        try encodeAny(@field(value, field_name), writer, seeker);
    }
}

test "round trip struct" {
    var out: [1000]u8 = undefined;
    const expected: struct { foo: u8, bar: ?u16 } = .{ .foo = 12, .bar = null };
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn encodeVector(value: anytype, writer: anytype, seeker: anytype) !void {
    const encoded_len = @typeInfo(@TypeOf(value)).vector.len;

    const format: Spec.Format = switch (encoded_len) {
        0...std.math.maxInt(u4) => .{ .fixarray = .{ .len = encoded_len } },
        std.math.maxInt(u4) + 1...std.math.maxInt(u16) => .{ .array_16 = {} },
        std.math.maxInt(u16) + 1...std.math.maxInt(u32) => .{ .array_32 = {} },
        else => @compileError("MessagePack only supports up to array length max u32."),
    };
    try writer.writeByte(format.encode());
    switch (format) {
        .fixarray => {},
        .array_16 => try writer.writeInt(u16, encoded_len, .big),
        .array_32 => try writer.writeInt(u32, encoded_len, .big),
        else => unreachable,
    }
    for (0..encoded_len) |i| {
        try encodeAny(value[i], writer, seeker);
    }
}

test "round trip vector" {
    var out: [356]u8 = undefined;
    const expected: @Vector(56, u8) = @splat(34);
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn encodeOptional(value: anytype, writer: anytype, seeker: anytype) !void {
    if (value) |non_null| {
        try encodeAny(non_null, writer, seeker);
    } else {
        const format = Spec.Format{ .nil = {} };
        try writer.writeByte(format.encode());
    }
}

test "round trip optional" {
    var out: [64]u8 = undefined;
    const expected: ?f64 = null;
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

test "round trip optional 2" {
    var out: [64]u8 = undefined;
    const expected: ?f64 = 12.3;
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn encodeArray(value: anytype, writer: anytype, seeker: anytype) !void {
    const has_sentinel = @typeInfo(@TypeOf(value)).array.sentinel != null;
    const encoded_len = @typeInfo(@TypeOf(value)).array.len + @as(comptime_int, @intFromBool(has_sentinel));

    const format: Spec.Format = switch (encoded_len) {
        0...std.math.maxInt(u4) => .{ .fixarray = .{ .len = encoded_len } },
        std.math.maxInt(u4) + 1...std.math.maxInt(u16) => .{ .array_16 = {} },
        std.math.maxInt(u16) + 1...std.math.maxInt(u32) => .{ .array_32 = {} },
        else => @compileError("MessagePack only supports up to array length max u32."),
    };
    try writer.writeByte(format.encode());
    switch (format) {
        .fixarray => {},
        .array_16 => try writer.writeInt(u16, encoded_len, .big),
        .array_32 => try writer.writeInt(u32, encoded_len, .big),
        else => unreachable,
    }
    for (value) |value_child| {
        try encodeAny(value_child, writer, seeker);
    }
    const Child = @typeInfo(@TypeOf(value)).array.child;
    if (@typeInfo(@TypeOf(value)).array.sentinel) |sentinel| {
        const sentinel_value: Child = @as(*const Child, @ptrCast(sentinel)).*;
        try encodeAny(sentinel_value, writer, seeker);
    }
}

test "round trip array" {
    var out: [64]u8 = undefined;
    const expected: [3]bool = .{ true, false, true };
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn encodeFloat(value: anytype, writer: anytype) !void {
    const format: Spec.Format = switch (@typeInfo(@TypeOf(value)).float.bits) {
        32 => .{ .float_32 = {} },
        64 => .{ .float_64 = {} },
        else => @compileError("MessagePack only supports 32 or 64 bit floats."),
    };
    try writer.writeByte(format.encode());
    switch (format) {
        .float_32 => try writer.writeInt(u32, @bitCast(value), .big),
        .float_64 => try writer.writeInt(u64, @bitCast(value), .big),
        else => unreachable,
    }
}

test "round trip float 64" {
    var out: [64]u8 = undefined;
    const expected: f64 = 12.35;
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

test "round trip float 32" {
    var out: [64]u8 = undefined;
    const expected: f32 = 12.35;
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

// TODO: maybe re-think this and use the smallest possible representation
fn encodeInt(value: anytype, writer: anytype) !void {
    const T = @TypeOf(value);

    if (@typeInfo(T).int.bits > 64) @compileError("MessagePack only supports up to 64 bit integers.");

    const format: Spec.Format = switch (@typeInfo(T).int.signedness) {
        .unsigned => switch (@typeInfo(T).int.bits) {
            0...7 => .{ .positive_fixint = .{ .value = value } },
            8 => .{ .uint_8 = {} },
            9...16 => .{ .uint_16 = {} },
            17...32 => .{ .uint_32 = {} },
            33...64 => .{ .uint_64 = {} },
            else => unreachable,
        },
        .signed => switch (@typeInfo(T).int.bits) {
            0...6 => blk: {
                if (value >= 0) {
                    break :blk .{ .positive_fixint = .{ .value = @intCast(value) } };
                } else if (value >= -32) {
                    break :blk .{ .negative_fixint = .{ .value = value } };
                } else {
                    break :blk .{ .int_8 = {} };
                }
            },
            7...8 => .{ .int_8 = {} },
            9...16 => .{ .int_16 = {} },
            17...32 => .{ .int_32 = {} },
            33...64 => .{ .int_64 = {} },
            else => unreachable,
        },
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

test "encode int" {
    var out1: [1]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &.{0x00}, try encode(@as(u5, 0), &out1));
    try std.testing.expectEqualSlices(u8, &.{0xFF}, try encode(@as(i5, -1), &out1));
    try std.testing.expectEqualSlices(u8, &.{0xE0}, try encode(@as(i6, -32), &out1));
}

fn encodeBool(value: anytype, writer: anytype) !void {
    if (value) {
        const format = Spec.Format{ .true = void{} };
        try writer.writeByte(format.encode());
    } else {
        const format = Spec.Format{ .false = void{} };
        try writer.writeByte(format.encode());
    }
}

test "encode bool" {
    var out: [1]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &.{0xc3}, try encode(true, &out));
    try std.testing.expectEqualSlices(u8, &.{0xc2}, try encode(false, &out));
}

test "roundtrip bool" {
    var out: [64]u8 = undefined;
    const expected = true;
    const slice = try encode(expected, &out);
    try std.testing.expectEqual(expected, decode(@TypeOf(expected), slice));
}

fn decodeAny(comptime T: type, reader: anytype, seeker: anytype) !T {
    switch (@typeInfo(T)) {
        .bool => return try decodeBool(reader),
        .int => return try decodeInt(T, reader),
        .float => return try decodeFloat(T, reader),
        .array => return try decodeArray(T, reader, seeker),
        .optional => return try decodeOptional(T, reader, seeker),
        .vector => return try decodeVector(T, reader, seeker),
        .@"struct" => return try decodeStruct(T, reader, seeker),
        .@"enum" => return try decodeEnum(T, reader),
        .@"union" => return try decodeUnion(T, reader, seeker),

        else => @compileError("type: " ++ @typeName(T) ++ " not supported."),
    }
    unreachable;
}

// TODO: refactor this to make it less garbage when inline for loops can have continue.
// https://github.com/ziglang/zig/issues/9524
fn decodeUnion(comptime T: type, reader: anytype, seeker: anytype) !T {
    _ = @typeInfo(T).@"union".tag_type orelse @compileError("Unions require a tag type.");
    const starting_position = try seeker.getPos();
    const rval = rval: inline for (comptime std.meta.fields(T)) |union_field| {
        const res = decodeAny(union_field.type, reader, seeker) catch |err| switch (err) {
            error.Invalid, error.EndOfStream => |err2| blk: {
                try seeker.seekTo(starting_position);
                break :blk err2;
            },
        };
        if (res) |good_res| {
            break :rval @unionInit(T, union_field.name, good_res);
        } else |err| switch (err) {
            error.Invalid, error.EndOfStream => {},
        }
    } else {
        return error.Invalid;
    };
    return rval;
}

test "decode union" {
    const MyUnion = union(enum) {
        my_u8: u8,
        my_bool: bool,
    };

    try std.testing.expectEqual(MyUnion{ .my_bool = false }, try decode(MyUnion, &.{0xc2}));
    try std.testing.expectEqual(MyUnion{ .my_u8 = 0 }, try decode(MyUnion, &.{0x00}));
    try std.testing.expectError(error.Invalid, decode(MyUnion, &.{0xc4}));
}

fn decodeEnum(comptime T: type, reader: anytype) !T {
    const TagInt = @typeInfo(T).@"enum".tag_type;
    const int: TagInt = try decodeInt(TagInt, reader);
    const res = std.meta.intToEnum(T, int) catch |err| switch (err) {
        error.InvalidEnumTag => return error.Invalid,
    };
    return res;
}

test "decode enum" {
    const TestEnum = enum {
        foo,
        bar,
    };
    try std.testing.expectEqual(TestEnum.foo, decode(TestEnum, &.{0x00}));
    try std.testing.expectEqual(TestEnum.bar, decode(TestEnum, &.{0x01}));
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

fn decodeStruct(comptime T: type, reader: anytype, seeker: anytype) !T {
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
                @field(res, field_name) = try decodeAny(@FieldType(T, field_name), reader, seeker);
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

    const bad_bytes2: []const u8 = &.{
        0b10000010, // map with two KV pairs
        0b10100011, // fix str 3 char
        'f',
        'o',
        'o',
        0x03,
        0b10100101, // fix str 5 char
        'b',
        'a',
        'z',
        'z',
        'z',
        0x02,
    };

    try std.testing.expectEqualDeep(Foo{}, try decode(Foo, bytes));
    try std.testing.expectEqualDeep(Foo2{}, try decode(Foo2, bytes));
    try std.testing.expectError(error.Invalid, decode(Foo2, bad_bytes));
    try std.testing.expectError(error.Invalid, decode(Foo2, bad_bytes2));
}

fn decodeOptional(comptime T: type, reader: anytype, seeker: anytype) !T {
    const format = Spec.Format.decode(try reader.readByte());

    const Child = @typeInfo(T).optional.child;
    switch (format) {
        .nil => return null,
        else => {
            // need to recover last byte we just consumed parsing the format.
            try seeker.seekBy(-1);
            return try decodeAny(Child, reader, seeker);
        },
    }
}

test "decode optional" {
    try std.testing.expectEqual(null, decode(?u8, &.{0xc0}));
    try std.testing.expectEqual(@as(u8, 1), decode(?u8, &.{0x01}));
}

fn decodeVector(comptime T: type, reader: anytype, seeker: anytype) error{ Invalid, EndOfStream }!T {
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
        res[i] = try decodeAny(Child, reader, seeker);
    }
    return res;
}

test "decode vector" {
    try std.testing.expectEqual(@Vector(3, bool){ true, false, true }, decode(@Vector(3, bool), &.{ 0b10010011, 0xc3, 0xc2, 0xc3 }));
}

fn decodeArray(comptime T: type, reader: anytype, seeker: anytype) error{ Invalid, EndOfStream }!T {
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
        res[i] = try decodeAny(Child, reader, seeker);
    }
    if (@typeInfo(T).array.sentinel) |sentinel| {
        const sentinel_value: Child = @as(*const Child, @ptrCast(sentinel)).*;
        if (try decodeAny(Child, reader, seeker) != sentinel_value) return error.Invalid;
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
const VarFBS = std.io.FixedBufferStream([]u8);

fn decodeBool(reader: anytype) error{ Invalid, EndOfStream }!bool {
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

fn decodeInt(comptime T: type, reader: anytype) error{ Invalid, EndOfStream }!T {
    const format = Spec.Format.decode(try reader.readByte());
    if (@typeInfo(T).int.bits > 64) @compileError("message pack does not support integers larger than 64 bits.");
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
        .negative_fixint => |val| return std.math.cast(T, val.value) orelse return error.Invalid,
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
    try std.testing.expectEqual(@as(i5, -1), decode(i5, &.{0xff}));
    try std.testing.expectError(error.Invalid, decode(i5, &.{0xb3}));
}

fn decodeFloat(comptime T: type, reader: anytype) error{ Invalid, EndOfStream }!T {
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
