const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const printf = root.printf;
const BoardInfo = root.HAL.BoardInfoController.BoardInfo;

const Forth = @import("../forty/forth.zig");

const Self = @This();

pub var board: BoardInfo = BoardInfo{};

pub fn defineModule(forth: *Forth) !void {
    try forth.defineConstant("board", @intFromPtr(&board));
    try forth.defineNamespace(Self, .{
        .{ "print", "print-board-info" },
        .{"name"},
        .{"version"},
        .{"processor"},
        .{"memory"},
        .{"manufacturer"},
        .{ "serialNumber", "serial-number" },
        .{ "macAddress", "mac-address" },
    });
}

pub fn init(allocator: Allocator) !void {
    board.init(allocator);

    root.hal.board_info_controller.inspect(&board) catch |err| {
        _ = printf("Board inspection error %s\n", @errorName(err).ptr);
    };
}

pub fn print() void {
    _ = printf("Board model %s (a %s) with %dMB\n\n", name().ptr, processor().ptr, memory().?);
    _ = printf("    MAC address: %08x\n", macAddress().?);
    _ = printf("  Serial number: %08x\n", serialNumber().?);
    _ = printf("Manufactured by: %s\n", manufacturer().ptr);

    for (board.memory.regions.items) |r| {
        try r.print();
    }
}

pub fn name() []const u8 {
    return board.model.name;
}

pub fn version() ?u8 {
    return board.model.version;
}

pub fn processor() []const u8 {
    return board.model.processor;
}

pub fn memory() ?u32 {
    return board.model.memory;
}

pub fn manufacturer() []const u8 {
    return board.device.manufacturer;
}

pub fn serialNumber() ?u32 {
    return board.device.serial_number;
}

pub fn macAddress() ?u32 {
    return board.device.mac_address;
}
