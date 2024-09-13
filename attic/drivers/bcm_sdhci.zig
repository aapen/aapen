const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const Driver = common.Driver;

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;

pub const ident = common.DriverIdent{
    .compatible = "brcm,bcm2835-sdhci",
    .detect = &detect,
    .deviceTreeParse = &deviceTreeParse,
};

fn deviceTreeParse(allocator: *Allocator, devicenode: *Node) !*anyopaque {
    _ = allocator;
    _ = devicenode;
    return common.Error.NotImplemented;
}

fn detect(allocator: *Allocator, options: *anyopaque) !*common.Driver {
    _ = allocator;
    _ = options;
    return common.Error.NotImplemented;
}
