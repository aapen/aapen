const std = @import("std");
const Allocator = std.mem.Allocator;

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;

pub const Error = error{
    OutOfMemory,
    NotImplemented,
    NoCompatibleDriver,
    InitializationError,
};

pub const DriverIdent = struct {
    compatible: []const u8,
    detect: DetectFn,
    deviceTreeParse: DeviceTreeParseFn,
};

pub const Driver = struct {
    attach: AttachFn,
    detach: DetachFn,

    name: []const u8,
};

/// Get the configuration for a device, given a devicetree node. The
/// return type is specific to the device class. If this returns an
/// error, the device's `detectFn` will not be called.
pub const DeviceTreeParseFn = *const fn (allocator: *Allocator, devicenode: *Node) Error!*anyopaque;

/// Verify the device exists, configure it, and return a vtable of its
/// operations. The value passed as `config` will be the same one that
/// was returned from the `deviceTreeParse` function
pub const DetectFn = *const fn (allocator: *Allocator, options: *anyopaque) Error!*Driver;

pub const Device = struct {
    driver: *Driver,
};

/// Attempt to "attach" the device. This completes initialization and
/// makes it available for use. On failure, detach does *not* need to
/// be called.
pub const AttachFn = *const fn (device: *Device) Error!void;

/// Attempt to "detach" the device. This removes it from active
/// use. If there is a physical interface, it is safe to disconnect
/// (unplug) the physical part after this.
pub const DetachFn = *const fn (device: *Device) Error!void;

// ----------------------------------------------------------------------
// Utilities
// ----------------------------------------------------------------------
