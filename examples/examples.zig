const std = @import("std");

const lizpack = @import("lizpack");

test "basic example" {
    const CustomerComplaint = struct {
        user_id: u64,
        status: enum(u8) {
            received,
            reviewed,
            awaiting_response,
            finished,
        },
    };

    var out: [1000]u8 = undefined;
    const expected: CustomerComplaint = .{ .user_id = 2345, .status = .reviewed };
    const slice: []u8 = try lizpack.encode(expected, &out);
    try std.testing.expectEqual(expected, lizpack.decode(@TypeOf(expected), slice));
}

test "basic example 2" {
    const TemperatureMeasurement = struct {
        station_id: u64,
        temperature_deg_c: f64,
        latitude_deg: f64,
        longitude_deg: f64,
        altitude_m: f64,
    };

    var out: [1000]u8 = undefined;
    const expected: TemperatureMeasurement = .{
        .station_id = 456,
        .temperature_deg_c = 34.2,
        .latitude_deg = 45.2,
        .longitude_deg = 23.234562,
        .altitude_m = 10034,
    };
    const slice: []u8 = try lizpack.encode(expected, &out);
    try std.testing.expectEqual(expected, lizpack.decode(@TypeOf(expected), slice));
}

test {
    var out: [1]u8 = undefined;
    const slice: []u8 = try lizpack.encode(false, &out);
    try std.testing.expectEqualSlices(u8, &.{0xc2}, slice);
}

test "basic customize encoding" {
    const CustomerComplaint = struct {
        uuid: [16]u8,
        message: []const u8,

        const format: lizpack.FormatOptions(@This()) = .{
            .layout = .map,
            .fields = .{
                .uuid = .bin,
                .message = .str,
            },
        };
    };

    var out: [1000]u8 = undefined;
    const expected: CustomerComplaint = .{
        .uuid = .{ 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .message = "Your software is horrible!",
    };
    const slice: []u8 = try lizpack.encodeCustom(expected, &out, .{ .format = CustomerComplaint.format });
    const decoded = try lizpack.decodeCustomAlloc(std.testing.allocator, CustomerComplaint, slice, .{
        .format = CustomerComplaint.format,
    });
    defer decoded.deinit();
    try std.testing.expectEqualDeep(
        expected,
        decoded.value,
    );
}

test "nested format customizations" {
    const Location = struct {
        city: []const u8,
        state: []const u8,
        pub const format: lizpack.FormatOptions(@This()) = .{
            .layout = .map,
            .fields = .{
                .city = .str,
                .state = .str,
            },
        };
    };
    const User = struct {
        username: []const u8,
        uuid: [16]u8,
        location: Location,

        pub const format: lizpack.FormatOptions(@This()) = .{
            .layout = .map,
            .fields = .{
                .username = .str,
                .uuid = .bin,
                .location = Location.format,
            },
        };
    };

    const my_user: User = .{
        .username = "foo",
        .uuid = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        .location = .{
            .city = "Los Angeles",
            .state = "California",
        },
    };

    var out: [1000]u8 = undefined;
    const expected = my_user;
    const slice = try lizpack.encodeCustom(expected, &out, .{ .format = User.format });
    const decoded = try lizpack.decodeCustomAlloc(std.testing.allocator, @TypeOf(expected), slice, .{ .format = User.format });
    defer decoded.deinit();
    try std.testing.expectEqualDeep(expected, decoded.value);
}

test "enum format customizations" {
    var out: [1000]u8 = undefined;
    const MyEnum = enum {
        foo,
        bar,

        pub const format_as_str: lizpack.FormatOptions(@This()) = .str;
        pub const format_as_int: lizpack.FormatOptions(@This()) = .int;
    };

    const slice = try lizpack.encodeCustom(MyEnum.foo, &out, .{ .format = MyEnum.format_as_str });
    try std.testing.expectEqualSlices(u8, &.{ 0b10100011, 'f', 'o', 'o' }, slice);

    const slice2 = try lizpack.encodeCustom(MyEnum.foo, &out, .{ .format = MyEnum.format_as_int });
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

test "union format customization" {
    const MyUnion = union(enum) {
        my_u8: u8,
        my_bool: bool,

        pub const format_as_map: lizpack.FormatOptions(@This()) = .{ .layout = .map };
        pub const format_as_active_field: lizpack.FormatOptions(@This()) = .{ .layout = .active_field };
    };

    const bytes_active_field: []const u8 = &.{(lizpack.Spec.Format{ .false = {} }).encode()};
    try std.testing.expectEqual(MyUnion{ .my_bool = false }, try lizpack.decodeCustom(MyUnion, bytes_active_field, .{ .format = MyUnion.format_as_active_field }));

    const bytes_map: []const u8 = &.{
        (lizpack.Spec.Format{ .fixmap = .{ .n_elements = 1 } }).encode(),
        (lizpack.Spec.Format{ .fixstr = .{ .len = 5 } }).encode(),
        'm',
        'y',
        '_',
        'u',
        '8',
        0x03,
    };
    try std.testing.expectEqual(MyUnion{ .my_u8 = 3 }, try lizpack.decodeCustom(MyUnion, bytes_map, .{ .format = MyUnion.format_as_map }));
}
