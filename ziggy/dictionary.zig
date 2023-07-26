const std = @import("std");
const print = std.debug.print;

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const reader = @import("reader.zig");
const string = @import("string.zig");

pub fn Entry(comptime DType: type, comptime FType: type) type {
    return struct {
        name: [20:0]u8,
        value: DType,
        flags: FType,

        const Self = @This();

        pub fn init(name: []const u8, value: DType, flags: FType) Self {
            var result = Self{
                .name = undefined,
                .value = value,
                .flags = flags,
            };
            string.copyTo(&result.name, name);
            return result;
        }
    };
}

pub fn Dictionary(comptime DType: type, comptime FType: type, comptime len: i32) type {
    const EntryDataType = Entry(DType, FType);

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

        pub fn put(self: *Self, name: []const u8, value: DType, flags: FType) !void {
            if (self.next_entry >= self.contents.len) {
                print("too many entries: {}\n", .{self.next_entry});
                return ForthError.TooManyEntries;
            }
            self.contents[@intCast(self.next_entry)] = EntryDataType.init(name, value, flags);
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
                printf("{s} ({}) => ", .{ entry.name, entry.flags });
                entry.value.pr(printf);
                printf("\n", .{});
                i -= 1;
            }
        }
    };
}

//pub fn main() !void {
//    const D1 = Dictionary(i32, 100);
//
//    var d = D1.init();
//
//    try d.put("foo", 1234);
//    try d.put("bar", 7717);
//    var v = try d.get("foo");
//    std.debug.print("rop: {}\n", .{v});
//
//    v = try d.get("bar");
//    print("bar: {}\n", .{v});
//
//    _ = try d.put("aaa", 111);
//    _ = try d.put("bbb", 222);
//    _ = try d.put("bbb", 212);
//
//    v = try d.get("bbb");
//    print("bbb: {}\n", .{v});
//
//    v = d.get("zzzz") catch 999999;
//    print("zzz: {}\n", .{v});
//
//    v = d.get("zzzz") catch |err| {
//        print("error {}\n", .{err});
//        return err;
//    };
//    print("zzzz: {}\n", .{v});
//}
