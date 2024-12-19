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

// format name first byte (in binary) first byte (in hex)
// positive fixint 0xxxxxxx 0x00 - 0x7f
// fixmap 1000xxxx 0x80 - 0x8f
// fixarray 1001xxxx 0x90 - 0x9f
// fixstr 101xxxxx 0xa0 - 0xbf
// nil 11000000 0xc0
// (never used) 11000001 0xc1
// false 11000010 0xc2
// true 11000011 0xc3
// bin 8 11000100 0xc4
// bin 16 11000101 0xc5
// bin 32 11000110 0xc6
// ext 8 11000111 0xc7
// ext 16 11001000 0xc8
// ext 32 11001001 0xc9
// float 32 11001010 0xca
// float 64 11001011 0xcb
// uint 8 11001100 0xcc
// uint 16 11001101 0xcd
// uint 32 11001110 0xce
// uint 64 11001111 0xcf
// int 8 11010000 0xd0
// int 16 11010001 0xd1
// int 32 11010010 0xd2
// int 64 11010011 0xd3
// fixext 1 11010100 0xd4
// fixext 2 11010101 0xd5
// fixext 4 11010110 0xd6
// fixext 8 11010111 0xd7
// fixext 16 11011000 0xd8
// str 8 11011001 0xd9
// str 16 11011010 0xda
// str 32 11011011 0xdb
// array 16 11011100 0xdc
// array 32 11011101 0xdd
// map 16 11011110 0xde
// map 32 11011111 0xdf
// negative fixint 111xxxxx 0xe0 - 0xff

test {
    std.testing.refAllDecls(@This());
}
