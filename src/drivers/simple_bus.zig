const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const bigToNative = std.mem.bigToNative;

const root = @import("root");
const kprint = root.kprint;
const kwarn = root.kwarn;
const kinfo = root.kinfo;

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;
const Property = devicetree.Fdt.Property;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;

pub const SimpleBus = struct {
    bus_ranges: AddressTranslations = undefined,
    dma_ranges: AddressTranslations = undefined,

    pub fn deviceTreeParse(self: *SimpleBus, node_name: []const u8) !void {
        const devicenode = try devicetree.global_devicetree.nodeLookupByPath(node_name);

        var bus_ranges = try devicenode.translations("ranges");
        self.bus_ranges = bus_ranges;

        var dma_ranges = try devicenode.translations("dma-ranges");
        self.dma_ranges = dma_ranges;
    }
};
