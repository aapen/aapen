const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;
const BoardInfo = root.HAL.BoardInfoController.BoardInfo;

const Forth = @import("../forty/forth.zig").Forth;

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
        kprint("Board inspection error {any}\n", .{err});
    };
}

pub fn print() void {
    kprint("Board model {s} (a {s}) with {?}MB\n\n", .{
        board.model.name,
        board.model.processor,
        board.model.memory,
    });
    kprint("    MAC address: {?}\n", .{board.device.mac_address});
    kprint("  Serial number: {?}\n", .{board.device.serial_number});
    kprint("Manufactured by: {?s}\n", .{board.device.manufacturer});

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
