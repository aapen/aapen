const std = @import("std");
const print = std.debug.print;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const reader = @import("reader.zig");
const string = @import("string.zig");

pub fn Entry(comptime DType: type) type {
    return struct {
        name: [20:0]u8,
        value: DType,
        immediate: bool,

        const Self = @This();

        pub fn init(name: []const u8, value: DType, immediate: bool) Self {
            var result = Self{
                .name = undefined,
                .value = value,
                .immediate = immediate,
            };
            string.copyTo(&result.name, name);
            return result;
        }
    };
}

pub fn Dictionary(comptime DType: type, comptime len: i32) type {
    const EntryDataType = Entry(DType);

    return struct {
        contents: [len]EntryDataType,
        next_entry: i32,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .contents = undefined,
                .next_entry = 0,
            };
        }

        pub fn put(self: *Self, name: []const u8, value: DType, immediate: bool) !void {
            if (self.next_entry >= self.contents.len) {
                print("too many entries: {}\n", .{self.next_entry});
                return ForthError.TooManyEntries;
            }
            self.contents[@intCast(self.next_entry)] = EntryDataType.init(name, value, immediate);
            self.next_entry += 1;
        }

        pub fn get(self: *Self, name: []const u8) !DType {
            var entry = try self.getEntry(name);
            return entry.value;
        }

        pub fn getEntry(self: *Self, name: []const u8) !EntryDataType {
            var i: i32 = self.next_entry - 1;

            while (i >= 0) {
                var j: usize = @intCast(i);
                var this_name = self.contents[j].name;
                var l = std.mem.indexOfSentinel(u8, 0, &this_name);
                if (std.mem.eql(u8, this_name[0..l], name)) {
                    return self.contents[j];
                }
                i -= 1;
            }
            return ForthError.NotFound;
        }

        pub fn pr(self: *Self, comptime printf: anytype) !void {
            var i: i32 = self.next_entry - 1;

            while (i >= 0) {
                var j: usize = @intCast(i);
                var entry = self.contents[j];
                printf("{s} ({}) => ", .{ entry.name, entry.immediate });
                entry.value.pr(printf);
                printf("\n", .{});
                i -= 1;
            }
        }
    };
}

test "Basic dictionary operation" {
    const D1 = Dictionary(i32, 100);

    var d = D1.init();

    try d.put("foo", 1234, false);
    try d.put("bar", 7717, false);
    var v = try d.get("foo");
    std.debug.print("rop: {}\n", .{v});

    v = try d.get("bar");
    print("bar: {}\n", .{v});

    _ = try d.put("aaa", 111, false);
    _ = try d.put("bbb", 222, false);
    _ = try d.put("bbb", 212, false);

    v = try d.get("bbb");
    print("bbb: {}\n", .{v});

    v = d.get("zzzz") catch 999999;
    print("zzz: {}\n", .{v});

}
