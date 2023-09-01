const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;
const kerror = root.kerror;
const kinfo = root.kinfo;

const common = @import("drivers/common.zig");
const DriverIdent = common.DriverIdent;
const Driver = common.Driver;
const Device = common.Device;
const Error = common.Error;

const devicetree = @import("devicetree.zig");
const Node = devicetree.Fdt.Node;

/// TODO: Should we find a way to conditionally compile this?
const driver_idents = [_]*const DriverIdent{
    &@import("drivers/simple_bus.zig").ident,
    &@import("drivers/bcm_sdhci.zig").ident,
    &@import("drivers/bcm_mailbox.zig").ident,
};

fn deviceIdentifyCompatibleDriver(node: *Node) !*const DriverIdent {
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
    return Error.NoCompatibleDriver;
}

fn deviceDetect(
    allocator: *Allocator,
    devicenode: *Node,
    ident: *const DriverIdent,
) !*Driver {
    var driver = try ident.detect(allocator, devicenode);

    kinfo(@src(), "Detected {s} as {s}\n", .{ devicenode.name, ident.compatible });

    return driver;
}

fn deviceConstruct(
    allocator: *Allocator,
    devicenode: *Node,
    ident: *const DriverIdent,
    driver: *Driver,
) !*Device {
    _ = devicenode;
    _ = ident;
    var device = try allocator.create(Device);

    device.* = .{
        .driver = driver,
    };

    return device;
}

pub fn deviceAttemptAttach(allocator: *Allocator, devicenode: *Node) !*Device {
    var ident = try deviceIdentifyCompatibleDriver(devicenode);
    var driver = try deviceDetect(allocator, devicenode, ident);
    return deviceConstruct(allocator, devicenode, ident, driver);
}

pub fn deviceAttemptAttachByPath(allocator: *Allocator, path: []const u8) ?*Device {
    var tree = devicetree.global_devicetree;
    var device_node = tree.nodeLookupByPath(path);

    if (device_node) |node| {
        return deviceAttemptAttach(allocator, node) catch |err| blk: {
            kerror(@src(), "Failed to load driver for {s} as {s}: {any}\n", .{ path, node.name, err });
            break :blk null;
        };
    } else |err| {
        kerror(@src(), "Error locating {s} devicetree node: {any}\n", .{ path, err });
        return null;
    }
}

pub fn init(allocator: *Allocator) void {
    const soc = deviceAttemptAttachByPath(allocator, "soc");
    _ = soc;
    const mbox = deviceAttemptAttachByPath(allocator, "mailbox");
    _ = mbox;
    // deviceAttemptAttachByPath(allocator, "mmc");
    // deviceAttemptAttachByPath(allocator, "dma");
}
