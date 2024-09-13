const std = @import("std");

const core = @import("core.zig");
const hidkbd = @import("hid_keyboard.zig");
const hidmouse = @import("hid_mouse.zig");
const hub = @import("hub.zig");
const spec = @import("spec.zig");

const DriverTableEntry = struct {
    class: ?u8,
    subclass: ?u8,
    protocol: ?u8,
    vendor: ?u8,
    product: ?u8,
    driver: *const Driver,
};

const driver_table_registry = .{
    .{ spec.USB_INTERFACE_CLASS_HUB, null, null, null, null, &hub.class_driver },
    .{ spec.USB_INTERFACE_CLASS_HID, spec.HID_SUBCLASS_BOOT, spec.HID_PROTOCOL_KEYBOARD, null, null, &hidkbd.class_driver },
    .{ spec.USB_INTERFACE_CLASS_HID, spec.HID_SUBCLASS_BOOT, spec.HID_PROTOCOL_MOUSE, null, null, &hidmouse.class_driver },
};

pub const driver_table: [driver_table_registry.len]DriverTableEntry = init: {
    var initial_value: [driver_table_registry.len]DriverTableEntry = undefined;
    for (&initial_value, 0..) |*t, i| {
        const dtr = &driver_table_registry[i];
        t.* = .{
            .class = dtr[0],
            .subclass = dtr[1],
            .protocol = dtr[2],
            .vendor = dtr[3],
            .product = dtr[4],
            .driver = dtr[5],
        };
    }
    break :init initial_value;
};

pub const Driver = struct {
    name: []const u8,
    initialize: *const fn (allocator: std.mem.Allocator) core.Error!void,
    bind: *const fn (port: *hub.HubPort, interface: u8) core.Error!void,
    unbind: ?*const fn (port: *hub.HubPort, interface: u8) core.Error!void,
};

pub fn initializeDrivers(alloc: std.mem.Allocator) !void {
    for (&driver_table) |*dte| {
        try dte.driver.initialize(alloc);
    }
}

pub fn findDriver(intf_class: u8, intf_subclass: u8, intf_protocol: u8, vendor: u16, product: u16) ?*const Driver {
    for (&driver_table) |*dte| {
        if ((dte.class == null or dte.class.? == intf_class) and
            (dte.subclass == null or dte.subclass.? == intf_subclass) and
            (dte.protocol == null or dte.protocol.? == intf_protocol) and
            (dte.vendor == null or dte.vendor.? == vendor) and
            (dte.product == null or dte.product.? == product))
        {
            return dte.driver;
        }
    }

    return null;
}
