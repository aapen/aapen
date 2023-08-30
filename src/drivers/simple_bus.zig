const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const bigToNative = std.mem.bigToNative;

const root = @import("root");
const kprint = root.kprint;
const kwarn = root.kwarn;

const common = @import("common.zig");
const Driver = common.Driver;
const Device = common.Device;

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;
const Property = devicetree.Fdt.Property;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;

const SimpleBus = struct {
    driver: common.Driver,
    devicenode: ?*Node,
    address_bits: usize,
    size_bits: usize,
    ranges: AddressTranslations,
    dma_ranges: AddressTranslations,
};

fn Attach(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn Detach(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn Query(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn Detect(allocator: *Allocator, devicenode: *Node) !*common.Driver {
    var bus: *SimpleBus = try allocator.create(SimpleBus);

    var address_cells = devicenode.addressCells();
    var size_cells = devicenode.sizeCells();

    var ranges = devicenode.translations("ranges") catch return common.Error.InitializationError;
    var dma_ranges = devicenode.translations("dma-ranges") catch return common.Error.InitializationError;

    bus.* = SimpleBus{
        .driver = common.Driver{
            .attach = Attach,
            .detach = Detach,
            .query = Query,
            .name = "simple-bus",
        },
        .devicenode = devicenode,
        .address_bits = 32 * address_cells,
        .size_bits = 32 * size_cells,
        .ranges = ranges,
        .dma_ranges = dma_ranges,
    };
    return &bus.driver;
}

pub const ident = common.DriverIdent{
    .compatible = "simple-bus",
    .detect = &Detect,
};
