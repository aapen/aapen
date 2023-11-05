const std = @import("std");

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;

pub const SimpleBus = struct {
    bus_ranges: AddressTranslations,
    dma_ranges: AddressTranslations,

    pub fn init(allocator: std.mem.Allocator) SimpleBus {
        return .{
            .bus_ranges = AddressTranslations.init(allocator),
            .dma_ranges = AddressTranslations.init(allocator),
        };
    }

    pub fn appendBusRange(self: *const SimpleBus, child_address: u64, parent_address: u64, length: usize) !void {
        var mut_self = @constCast(self);
        try mut_self.bus_ranges.append(memory.translation(child_address, parent_address, length));
    }

    pub fn appendDmaRange(self: *const SimpleBus, child_address: u64, parent_address: u64, length: usize) !void {
        var mut_self = @constCast(self);
        try mut_self.dma_ranges.append(memory.translation(child_address, parent_address, length));
    }
};
