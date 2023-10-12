const std = @import("std");
const Allocator = std.mem.Allocator;

const memory = @import("../../memory.zig");
const Regions = memory.Regions;
const Region = memory.Region;

pub const BoardInfo = struct {
    pub const Model = struct {
        name: []const u8 = undefined,
        version: ?u8 = null,
        processor: []const u8 = undefined,
        memory: ?u32 = null,
        pcb_revision: ?u32 = null,
    };

    pub const Device = struct {
        manufacturer: []const u8 = undefined,
        serial_number: ?u32 = null,
        mac_address: ?u32 = null,
    };

    pub const Memory = struct {
        regions: memory.Regions = undefined,
    };

    model: Model = Model{},
    device: Device = Device{},
    memory: Memory = Memory{},

    pub fn init(self: *BoardInfo, allocator: *Allocator) void {
        self.memory.regions = memory.Regions.init(allocator.*);
    }
};

pub const BoardInfoController = struct {
    inspect: *const fn (board_info_controller: *BoardInfoController, info: *BoardInfo) void,
};
