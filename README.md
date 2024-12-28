# lizpack

A MessagePack Library for Zig

1. Zero allocations.
1. Simple control flow.
1. All messages validated for you.

A simple API:

```zig
pub fn encode(value: anytype, out: []u8) error{NoSpaceLeft}![]u8 {...}

pub fn decode(comptime T: type, in: []const u8) error{Invalid}!T {...}
```

Combines with your definition of your message structure:

```zig
const CustomerComplaint = struct {
    user_id: u64,
    status: enum(u8) {
        received,
        reviewed,
        awaiting_response,
        finished,
    },
};
```

## Default Formats

| Zig Type         | MessagePack Type                    |
| ---------------- | ----------------------------------- |
| `bool`           | bool                                |
| `null`           | nil                                 |
| `u3`,`u45`, `i6` | integer                             |
| `?T`             | nil or T                            |
| `enum`           | integer                             |
| `[N]T`           | N length array of T                 |
| `[N:x]T`         | N+1 length array of T ending in x   |
| `[N]u8`          | bin                                 |
| `@Vector(N, T)`  | N length array of T                 |
| `struct`         | map, str: field value               |
| `union (enum)`   | map (single key-value pair)         |
| `[]T`            | N length array of T                 |
| `[:x]T`          | N + 1 length array of T ending in x |
| `[]u8`           | bin                                 |
| `[:x]u8`         | bin ending in x                     |
| `*T`             | T                                   |

Unsupported types:

| Zig Type           | Reason                                                       |
| ------------------ | ------------------------------------------------------------ |
| `union` (untagged) | Decoding cannot determine active field, and neither can you. |

Note: pointer types require allocation to decode.

## Customizing Formats

You can customize how types are formatted in message pack:

| Zig Type       | Available Encodings                       |
| -------------- | ----------------------------------------- |
| `enum`         | string, int                               |
| `[]u8`,`[N]u8` | string, int, array                        |
| `struct`       | map, array                                |
| `union (enum)` | map (single key-value pair), active field |

See [examples](examples/examples.zig) for how to do it.

## Examples

```zig
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

```

More examples can be found in [examples/](/examples/).

## Installation

To add lizpack to your project as a dependency, run:

```sh
zig fetch --save git+https://github.com/kj4tmp/lizpack
```

Then add the following to your build.zig:

```zig
// assuming you have an existing executable called `exe`
const lizpack = b.dependency("lizpack", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("lizpack", lizpack.module("lizpack"));
```

And import the library to begin using it:

```zig
const lizpack = @import("lizpack");
```

## Coming Soon

1. Explicit allocation to support variable length and large messages (slices and pointers).
1. Customization of encoding / decoding (structs as arrays instead of maps, enums as strings, etc.).
