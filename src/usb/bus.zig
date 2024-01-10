/// A USB bus is a tree of devices rooted at the built-in hub.
const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.usb_bus);

// This pair of definitions connects the generic USB subsystem in
// this module to the hardware-specific portion under src/hal/*.zig.
const root = @import("root");
pub const HCI = root.HAL.USBHCI;
pub const Device = HCI.Device;

const descriptor = @import("descriptor.zig");
const DescriptorType = descriptor.DescriptorType;

const hub = @import("hub.zig");
const Hub = hub.Hub;

const Self = @This();

const Error = error{
    NotInitialized,
    BadTopology,
    InvalidResponse,
};

hub: Hub = undefined,

// Call this after the hardware is initialized.
pub fn init(self: *Self, allocator: Allocator, hci: *HCI, root_device: *Device) !void {
    if (root_device == undefined) {
        log.err("Root device is not defined, HCD may not be initialized", .{});
        return Error.NotInitialized;
    }

    if (!root_device.device_descriptor.isHub()) {
        log.err("Root device is not a hub. Something is very odd", .{});
        return Error.BadTopology;
    }

    self.hub = .{
        .host = hci,
        .device = root_device,
    };

    log.debug("Initialize builtin hub", .{});

    try self.hub.initialize(allocator);
}
