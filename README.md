# lizpack

A MessagePack Library for Zig

| Zig Type         | Encodes As MessagePack Type                                          | Decodes From MessagePack Type                             |
| ---------------- | -------------------------------------------------------------------- | --------------------------------------------------------- |
| `bool`           | bool                                                                 | bool                                                      |
| `null`           | nil                                                                  | nil                                                       |
| `u3`,`u45`, `i6` | integer                                                              | integer                                                   |
| `?T`             | nil or T                                                             | nil or T                                                  |
| `enum`           | integer                                                              | integer                                                   |
| `[N]T`           | N length array of T                                                  | N length array of T                                       |
| `[N:x]T`         | N+1 length array of T ending in x                                    | N+1 length array of T ending in x                         |
| `@Vector(N, T)`  | N length array of T                                                  | N length array of T                                       |
| `struct`         | map, keys are fields (orded by declaration), values are field values | map, keys are fields (unordered), values are field values |
| `union (enum)`   | active field                                                         | first successful field (ordered by declaration)           |
| `union`          | not yet supported                                                    | not yet supported                                         |
| `[]T`            | not yet supported                                                    | not yet supported                                         |
| `*T`             | not yet supported                                                    | not yet supported                                         |

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
