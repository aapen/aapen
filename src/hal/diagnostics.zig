const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;
const BoardInfo = root.HAL.BoardInfoController.BoardInfo;

pub var board: BoardInfo = BoardInfo{};

pub fn init(allocator: Allocator) !void {
    board.init(allocator);

    root.hal.board_info_controller.inspect(&board) catch |err| {
        kprint("Board inspection error {any}\n", .{err});
    };

    kprint("Board model {s} (a {s}) with {?}MB\n\n", .{
        board.model.name,
        board.model.processor,
        board.model.memory,
    });
    kprint("    MAC address: {?}\n", .{board.device.mac_address});
    kprint("  Serial number: {?}\n", .{board.device.serial_number});
    kprint("Manufactured by: {?s}\n\n", .{board.device.manufacturer});

    for (board.memory.regions.items) |r| {
        try r.print();
    }
}
