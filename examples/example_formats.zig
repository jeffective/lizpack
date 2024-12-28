const std = @import("std");

const lizpack = @import("lizpack");

test "enum format customizations" {
    var out: [1000]u8 = undefined;
    const MyEnum = enum {
        foo,
        bar,
        /// formats as a message pack string "foo"
        pub const format: lizpack.FormatOptions(@This()) = .str;
        /// formats as a message pack integer
        pub const format2: lizpack.FormatOptions(@This()) = .int;
    };

    const slice = try lizpack.encodeCustom(MyEnum.foo, &out, .{ .format = MyEnum.format });
    try std.testing.expectEqualSlices(u8, &.{ 0b10100011, 'f', 'o', 'o' }, slice);

    const slice2 = try lizpack.encodeCustom(MyEnum.foo, &out, .{ .format = MyEnum.format2 });
    try std.testing.expectEqualSlices(u8, &.{0}, slice2);
}

test "array and slice format customizations" {
    var out: [1000]u8 = undefined;
    const my_string: []const u8 = "foo";

    const format_as_bin: lizpack.FormatOptions(@TypeOf(my_string)) = .bin;
    const slice = try lizpack.encodeCustom(my_string, &out, .{ .format = format_as_bin });
    try std.testing.expectEqualSlices(u8, &.{ (lizpack.Spec.Format{ .bin_8 = {} }).encode(), 3, 'f', 'o', 'o' }, slice);

    const format_as_string: lizpack.FormatOptions(@TypeOf(my_string)) = .str;
    const slice2 = try lizpack.encodeCustom(my_string, &out, .{ .format = format_as_string });
    try std.testing.expectEqualSlices(u8, &.{ 0b10100011, 'f', 'o', 'o' }, slice2);

    const format_as_array: lizpack.FormatOptions(@TypeOf(my_string)) = .array;
    const slice3 = try lizpack.encodeCustom(my_string, &out, .{ .format = format_as_array });
    try std.testing.expectEqualSlices(u8, &.{
        (lizpack.Spec.Format{ .fixarray = .{ .len = 3 } }).encode(),
        (lizpack.Spec.Format{ .uint_8 = {} }).encode(),
        'f',
        (lizpack.Spec.Format{ .uint_8 = {} }).encode(),
        'o',
        (lizpack.Spec.Format{ .uint_8 = {} }).encode(),
        'o',
    }, slice3);
}
