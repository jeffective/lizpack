//! The MessagePack Specification
//!
//! Ref: https://github.com/msgpack/msgpack/blob/master/spec.md

const std = @import("std");

pub const Format = union(enum) {
    positive_fixint: packed struct(u8) {
        value: u7,
        _reserved: u1 = 0b0,
    },
    fixmap: packed struct(u8) {
        n_elements: u4,
        _reserved: u4 = 0b1000,
    },
    fixarray: packed struct(u8) {
        len: u4,
        _reserved: u4 = 0b1001,
    },
    fixstr: packed struct(u8) {
        len: u5,
        _reserved: u3 = 0b101,
    },
    nil,
    never_used,
    false,
    true,
    bin_8,
    bin_16,
    bin_32,
    ext_8,
    ext_16,
    ext_32,
    float_32,
    float_64,
    uint_8,
    uint_16,
    uint_32,
    uint_64,
    int_8,
    int_16,
    int_32,
    int_64,
    fixext_1,
    fixext_2,
    fixext_4,
    fixext_8,
    fixext_16,
    str_8,
    str_16,
    str_32,
    array_16,
    array_32,
    map_16,
    map_32,
    negative_fixint: packed struct {
        negative_value: u5,
        _reserved: u3 = 0b111,
    },

    pub fn decode(byte: u8) Format {
        switch (byte) {
            0x00...0x7f => return .{ .positive_fixint = @bitCast(byte) },
            0x80...0x8f => return .{ .fixmap = @bitCast(byte) },
            0x90...0x9f => return .{ .fixarray = @bitCast(byte) },
            0xa0...0xbf => return .{ .fixstr = @bitCast(byte) },
            0xc0 => return .nil,
            0xc1 => return .never_used,
            0xc2 => return .false,
            0xc3 => return .true,
            0xc4 => return .bin_8,
            0xc5 => return .bin_16,
            0xc6 => return .bin_32,
            0xc7 => return .ext_8,
            0xc8 => return .ext_16,
            0xc9 => return .ext_32,
            0xca => return .float_32,
            0xcb => return .float_64,
            0xcc => return .uint_8,
            0xcd => return .uint_16,
            0xce => return .uint_32,
            0xcf => return .uint_64,
            0xd0 => return .int_8,
            0xd1 => return .int_16,
            0xd2 => return .int_32,
            0xd3 => return .int_64,
            0xd4 => return .fixext_1,
            0xd5 => return .fixext_2,
            0xd6 => return .fixext_4,
            0xd7 => return .fixext_8,
            0xd8 => return .fixext_16,
            0xd9 => return .str_8,
            0xda => return .str_16,
            0xdb => return .str_32,
            0xdc => return .array_16,
            0xdd => return .array_32,
            0xde => return .map_16,
            0xdf => return .map_32,
            0xe0...0xff => return .{ .negative_fixint = @bitCast(byte) },
        }
    }
};

test "format identify from byte" {
    try std.testing.expectEqual(Format{ .positive_fixint = .{ .value = 0 } }, Format.decode(0));
    try std.testing.expectEqual(Format{ .positive_fixint = .{ .value = 4 } }, Format.decode(4));
    try std.testing.expectEqual(Format.nil, Format.decode(0xc0));
}

test {
    std.testing.refAllDecls(@This());
}
