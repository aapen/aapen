const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const bigToNative = std.mem.bigToNative;

const root = @import("root");
const kprint = root.kprint;
const kwarn = root.kwarn;
const kinfo = root.kinfo;

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
    options: *SimpleBusOptions,
};

fn attach(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn detach(_: *Device) !void {
    return common.Error.NotImplemented;
}

fn detect(allocator: *Allocator, options: *anyopaque) !*common.Driver {
    var bus: *SimpleBus = try allocator.create(SimpleBus);

    bus.* = SimpleBus{
        .driver = common.Driver{
            .attach = attach,
            .detach = detach,
            .name = "simple-bus",
        },
        .options = @ptrCast(@alignCast(options)),
    };

    return &bus.driver;
}

pub const SimpleBusOptions = struct {
    address_cells: usize,
    size_cells: usize,
    ranges: AddressTranslations,
    dma_ranges: AddressTranslations,
};

fn deviceTreeParse(allocator: *Allocator, devicenode: *Node) !*anyopaque {
    var bus_options: *SimpleBusOptions = try allocator.create(SimpleBusOptions);

    var address_cells = devicenode.addressCells();
    var size_cells = devicenode.sizeCells();

    var ranges = devicenode.translations("ranges") catch return common.Error.InitializationError;
    var dma_ranges = devicenode.translations("dma-ranges") catch return common.Error.InitializationError;

    bus_options.* = SimpleBusOptions{
        .address_cells = address_cells,
        .size_cells = size_cells,
        .ranges = ranges,
        .dma_ranges = dma_ranges,
    };

    return bus_options;
}

pub const ident = common.DriverIdent{
    .compatible = "simple-bus",
    .detect = &detect,
    .deviceTreeParse = &deviceTreeParse,
};
