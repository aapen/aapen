const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const string = @import("string.zig");

pub fn Dictionary(comptime DType: type) type {
    const EntryDataType = struct {
        name: [20:0]u8,
        value: DType,
        immediate: bool,

        const Self = @This();

        pub fn init(name: []const u8, value: DType, immediate: bool) Self {
            var self = Self{
                .name = undefined,
                .value = value,
                .immediate = immediate,
            };
            string.copyTo(&self.name, name);
            return self;
        }
    };

    return struct {
        allocator: Allocator,
        contents: ArrayList(EntryDataType),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
                .contents = ArrayList(EntryDataType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.contents.deinit();
        }

        pub fn put(self: *Self, name: []const u8, value: DType, immediate: bool) !void {
            try self.contents.append(EntryDataType.init(name, value, immediate));
        }

        pub fn get(self: *Self, name: []const u8) !DType {
            var entry = try self.getEntry(name);
            return entry.value;
        }

        fn isEmpty(self: *Self) bool {
            return self.contents.items.len == 0;
        }

        pub fn getEntry(self: *Self, name: []const u8) !EntryDataType {
            if (self.isEmpty()) {
                return ForthError.NotFound;
            }

            // TODO - how to iterate this in reverse?
            var i: i32 = @as(i32, @intCast(self.contents.items.len)) - 1;
            while (i >= 0) {
                const entry = self.contents.items[@intCast(i)];
                var this_name = entry.name;
                var l = std.mem.indexOfSentinel(u8, 0, &this_name);
                if (std.mem.eql(u8, this_name[0..l], name)) {
                    return entry;
                }
                i -= 1;
            }

            return ForthError.NotFound;
        }

        pub fn pr(self: *Self, writer: anytype) !void {
            for (self.contents.items) |entry| {
                try writer.print("{s} ({}) => {any}\n", .{ entry.name, entry.immediate, entry.value });
            }
        }
    };
}

test "Basic dictionary operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(gpa.deinit() == .ok) catch @panic("leak");
    var allocator = gpa.allocator();

    const print = std.debug.print;
    const assert = std.debug.assert;

    const D1 = Dictionary(i32);

    var d = D1.init(allocator);
    defer d.deinit();

    assert(d.isEmpty());

    try d.put("foo", 1234, false);
    try d.put("bar", 7717, false);

    assert(!d.isEmpty());

    var v = try d.get("foo");
    print("rop: {}\n", .{v});
    assert(v == 1234);

    v = try d.get("bar");
    print("bar: {}\n", .{v});
    assert(v == 7717);

    _ = try d.put("aaa", 111, false);
    _ = try d.put("bbb", 222, false);
    _ = try d.put("bbb", 212, false);

    v = try d.get("bbb");
    print("bbb: {}\n", .{v});
    assert(v == 212);

    v = d.get("zzzz") catch 999999;
    print("zzz: {}\n", .{v});

    //try d.pr(std.debug.print);
}
