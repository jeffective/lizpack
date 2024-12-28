const std = @import("std");

const lizpack = @import("lizpack");

test {
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

test {
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

test "customize encoding" {
    const CustomerComplaint = struct {
        uuid: [16]u8,
        message: []const u8,
    };

    var out: [1000]u8 = undefined;
    const expected: CustomerComplaint = .{
        .uuid = .{ 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        .message = "Your software is horrible!",
    };
    const slice: []u8 = try lizpack.encode(expected, &out);
    const decoded = try lizpack.decodeCustomAlloc(std.testing.allocator, CustomerComplaint, slice, .{ .format = .{ .fields = .{ .uuid = .bin } } });
    defer decoded.deinit();
    try std.testing.expectEqualDeep(
        expected,
        decoded.value,
    );
}
