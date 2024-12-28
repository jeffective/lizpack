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
