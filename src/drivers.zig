const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;
const kerror = root.kerror;
const kinfo = root.kinfo;

const common = @import("drivers/common.zig");
const devicetree = @import("devicetree.zig");
const Node = devicetree.Fdt.Node;

/// TODO: Should we find a way to conditionally compile this?
const driver_idents = [_]*const common.DriverIdent{
    &@import("drivers/simple_bus.zig").ident,
    &@import("drivers/bcm_sdhci.zig").ident,
};

fn findCompatibleDriver(node: *Node) ?*const common.DriverIdent {
    if (node.property("compatible")) |prop| {
        var compat = prop.valueAsString();
        // strip trailing null
        // var compat_clean = compat[0 .. compat.len - 1];
        for (driver_idents) |di| {
            if (std.mem.eql(u8, compat, di.compatible)) {
                return di;
            }
        }
    }
    return null;
}

fn detectDriver(
    allocator: *Allocator,
    devicenode: *Node,
    ident: *const common.DriverIdent,
) ?*common.Driver {
    kinfo(@src(), "Detected {s} as {s}\n", .{ devicenode.name, ident.compatible });

    var driver = ident.detect(allocator, devicenode) catch |err| {
        kerror(@src(), "error initializing driver: {any}\n", .{err});
        return null;
    };

    if (driver) |d| {
        //   attach the device
        _ = d;
    }

    return driver;
}

pub fn init(allocator: *Allocator) void {
    // get nodes at top of device tree
    const root_node = devicetree.root_node;
    const children = root_node.children.items;
    for (children) |child| {
        if (findCompatibleDriver(child)) |ident| {
            var driver = detectDriver(allocator, child, ident);

            _ = driver;
        }
    }
}
