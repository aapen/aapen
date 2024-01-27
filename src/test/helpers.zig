const std = @import("std");

const root = @import("root");
const printf = root.printf;

const qemu = @import("qemu.zig");

pub fn exit(status: u8) noreturn {
    qemu.exit(status);
    unreachable;
}

pub fn exitWithTestResult() noreturn {
    if (any_test_error) {
        _ = printf("... FAILED\n");
        exit(255);
    } else {
        _ = printf("... OK\n");
        exit(0);
    }
    unreachable;
}

pub var allocator: std.mem.Allocator = undefined;

var any_test_error = false;

// 'expect' functions here are modified versions from the Zig
// standard library. They have been altered to use printf() instead of
// std.debug.print so we can avoid writing an entire OS interface just
// to make Zig happy.

// These also set the mutable variable 'any_test_error' instead of
// returning a Zig error so we can report multiple test failures in a
// single execution.

pub fn expect(ok: bool) void {
    if (!ok) {
        _ = printf("error\n");
        any_test_error = true;
    }
}

pub fn expectEqual(expected: anytype, actual: @TypeOf(expected)) void {
    switch (@typeInfo(@TypeOf(actual))) {
        .NoReturn,
        .Opaque,
        .Frame,
        .AnyFrame,
        => @compileError("value of type " ++ @typeName(@TypeOf(actual)) ++ " encountered"),

        .Undefined,
        .Null,
        .Void,
        => return,

        .Type => {
            if (actual != expected) {
                _ = printf("expected type %s, found type %s\n", @typeName(expected).ptr, @typeName(actual).ptr);
                any_test_error = true;
            }
        },

        .Bool => {
            if (actual != expected) {
                _ = printf("expected %d, found %d\n", expected, actual);
                any_test_error = true;
            }
        },

        .Enum,
        .EnumLiteral,
        .Int,
        .Float,
        .ComptimeFloat,
        .ComptimeInt,
        => {
            if (actual != expected) {
                var buf_act: [256]u8 = undefined;
                const b = std.fmt.bufPrint(&buf_act, "expected {}, found {}", .{ expected, actual }) catch "";
                _ = printf("%s\n", b.ptr);
                any_test_error = true;
            }
        },

        .Fn,
        .ErrorSet,
        => {
            if (actual != expected) {
                _ = printf("expected fn differs from actual\n");
                any_test_error = true;
            }
        },

        .Pointer => |pointer| {
            switch (pointer.size) {
                .One, .Many, .C => {
                    if (actual != expected) {
                        _ = printf("expected 0x%08x, found 0x%08x\n", expected, actual);
                        any_test_error = true;
                    }
                },
                .Slice => {
                    if (actual.ptr != expected.ptr) {
                        _ = printf("expected slice ptr 0x%08x, found 0x%08x\n", expected.ptr, actual.ptr);
                        any_test_error = true;
                    }
                    if (actual.len != expected.len) {
                        _ = printf("expected slice len %d, found %d\n", expected.len, actual.len);
                        any_test_error = true;
                    }
                },
            }
        },

        .Array => |array| try expectEqualSlices(array.child, &expected, &actual),

        .Vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (!std.meta.eql(expected[i], actual[i])) {
                    _ = printf(
                        "index %d incorrect. expected %d, found %d\n",
                        i,
                        expected[i],
                        actual[i],
                    );
                    any_test_error = true;
                }
            }
        },

        .Struct => |structType| {
            inline for (structType.fields) |field| {
                try expectEqual(@field(expected, field.name), @field(actual, field.name));
            }
        },

        .Union => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Unable to compare untagged union values");
            }

            const Tag = std.meta.Tag(@TypeOf(expected));

            const expectedTag = @as(Tag, expected);
            const actualTag = @as(Tag, actual);

            try expectEqual(expectedTag, actualTag);

            // we only reach this loop if the tags are equal
            inline for (std.meta.fields(@TypeOf(actual))) |fld| {
                if (std.mem.eql(u8, fld.name, @tagName(actualTag))) {
                    try expectEqual(@field(expected, fld.name), @field(actual, fld.name));
                    return;
                }
            }

            // we iterate over *all* union fields
            // => we should never get here as the loop above is
            //    including all possible values.
            unreachable;
        },

        .Optional => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqual(expected_payload, actual_payload);
                } else {
                    _ = printf("expected some, found null\n");
                    any_test_error = true;
                }
            } else {
                if (actual) |actual_payload| {
                    _ = actual_payload;
                    _ = printf("expected null, found some\n");
                    any_test_error = true;
                }
            }
        },

        .ErrorUnion => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqual(expected_payload, actual_payload);
                } else |actual_err| {
                    _ = printf("expected result, found error %s\n", expected_payload, @errorName(actual_err));
                    any_test_error = true;
                }
            } else |expected_err| {
                if (actual) |actual_payload| {
                    _ = actual_payload;
                    _ = printf("expected error %s, found result\n", @errorName(expected_err));
                    any_test_error = true;
                } else |actual_err| {
                    try expectEqual(expected_err, actual_err);
                }
            }
        },
    }
}

pub fn expectEqualSlices(comptime T: type, expected: []const T, actual: []const T) void {
    if (expected.ptr == actual.ptr and expected.len == actual.len) {
        return;
    }

    const diff_index: usize = diff_index: {
        const shortest = @min(expected.len, actual.len);
        var index: usize = 0;
        while (index < shortest) : (index += 1) {
            if (!std.meta.eql(actual[index], expected[index])) break :diff_index index;
        }
        break :diff_index if (expected.len == actual.len) return else shortest;
    };

    _ = printf("slices differ. first difference occurs at index %d (0x%X)\n", diff_index, diff_index);

    // TODO: Should this be configurable by the caller?
    const max_lines: usize = 16;
    const max_window_size: usize = if (T == u8) max_lines * 16 else max_lines;

    // Print a maximum of max_window_size items of each input, starting just before the
    // first difference to give a bit of context.
    var window_start: usize = 0;
    if (@max(actual.len, expected.len) > max_window_size) {
        const alignment = if (T == u8) 16 else 2;
        window_start = std.mem.alignBackward(usize, diff_index - @min(diff_index, alignment), alignment);
    }
    const expected_window = expected[window_start..@min(expected.len, window_start + max_window_size)];
    const expected_truncated = window_start + expected_window.len < expected.len;
    const actual_window = actual[window_start..@min(actual.len, window_start + max_window_size)];
    const actual_truncated = window_start + actual_window.len < actual.len;

    var differ = if (T == u8) BytesDiffer{
        .expected = expected_window,
        .actual = actual_window,
    } else SliceDiffer(T){
        .start_index = window_start,
        .expected = expected_window,
        .actual = actual_window,
    };

    _ = printf("\n============ expected this output: =============  len: %d (0x%X)\n\n", expected.len, expected.len);
    if (window_start > 0) {
        _ = printf("... truncated, start index: 0x%X ...\n", window_start);
    }
    differ.print() catch {};
    if (expected_truncated) {
        const end_offset = window_start + expected_window.len;
        const num_missing_items = expected.len - (window_start + expected_window.len);
        _ = printf("... truncated, indexes [0x%X..] not shown, remaining bytes: 0x%X...\n", end_offset, num_missing_items);
    }

    // now reverse expected/actual and print again
    differ.expected = actual_window;
    differ.actual = expected_window;
    _ = printf("\n============= instead found this: ==============  len: %d (0x%X)\n\n", actual.len, actual.len);
    if (window_start > 0) {
        _ = printf("... truncated, start index: 0x%X ...\n", window_start);
    }
    differ.print() catch {};
    if (actual_truncated) {
        const end_offset = window_start + actual_window.len;
        const num_missing_items = actual.len - (window_start + actual_window.len);
        _ = printf("... truncated, indexes [0x%X..] not shown, remaining bytes: 0x%X ...\n", end_offset, num_missing_items);
    }
    _ = printf("\n================================================\n\n");

    any_test_error = true;
}

const BytesDiffer = struct {
    expected: []const u8,
    actual: []const u8,

    pub fn print(self: BytesDiffer) !void {
        var expected_iterator = ChunkIterator{ .bytes = self.expected };
        while (expected_iterator.next()) |chunk| {
            // to avoid having to calculate diffs twice per chunk
            for (chunk, 0..) |byte, i| {
                _ = printf("%02x ", byte);
                if (i == 7) _ = printf(" ");
            }
            _ = printf(" ");

            if (chunk.len < 16) {
                var missing_columns = (16 - chunk.len) * 3;
                if (chunk.len < 8) missing_columns += 1;
                for (0..missing_columns) |_| {
                    _ = printf(" ");
                }
            }
            for (chunk, 0..) |byte, i| {
                _ = i;
                const byte_to_print = if (std.ascii.isPrint(byte)) byte else '.';
                _ = printf("%c", byte_to_print);
            }
            _ = printf("\n");
        }
    }

    const ChunkIterator = struct {
        bytes: []const u8,
        index: usize = 0,

        pub fn next(self: *ChunkIterator) ?[]const u8 {
            if (self.index == self.bytes.len) return null;

            const start_index = self.index;
            const end_index = @min(self.bytes.len, start_index + 16);
            self.index = end_index;
            return self.bytes[start_index..end_index];
        }
    };
};

fn SliceDiffer(comptime T: type) type {
    return struct {
        start_index: usize,
        expected: []const T,
        actual: []const T,

        const Self = @This();

        pub fn print(self: Self) !void {
            for (self.expected, 0..) |value, i| {
                const full_index = self.start_index + i;

                if (@typeInfo(T) == .Pointer) {
                    _ = printf("[%d] %08x: %x\n", full_index, value, value);
                } else {
                    _ = printf("[%d]: %x\n", full_index, value);
                }
            }
        }
    };
}

pub fn expectError(expected_error: anyerror, actual_error_union: anytype) void {
    if (actual_error_union) |_| {
        _ = printf("expected error %s, found result\n", @errorName(expected_error).ptr);
        any_test_error = true;
    } else |actual_error| {
        if (expected_error != actual_error) {
            _ = printf("expected error %s, found error %s\n", @errorName(expected_error).ptr, @errorName(actual_error).ptr);
            any_test_error = true;
        }
    }
}
