const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const common = @import("common.zig");
const Driver = common.Driver;
const Device = common.Device;

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;

const SimpleBus = struct {
    driver: common.Driver,
    devicenode: ?*Node,
    address_size: usize, // size of an address, in u32s
    size_size: usize, // size of an index into a range, in u32s
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

fn Detect(allocator: *Allocator, devicenode: ?*Node) !?*common.Driver {
    var bus: *SimpleBus = try allocator.create(SimpleBus);
    bus.* = SimpleBus{
        .driver = common.Driver{
            .attach = Attach,
            .detach = Detach,
            .query = Query,
            .name = "simple-bus",
        },
        .devicenode = devicenode,
        .address_size = undefined,
        .size_size = undefined,
    };
    return &bus.driver;
}

pub const ident = common.DriverIdent{
    .compatible = "simple-bus",
    .detect = &Detect,
};
