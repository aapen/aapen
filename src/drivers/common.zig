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
};

pub const Driver = struct {
    attach: AttachFn,
    detach: DetachFn,
    query: QueryFn,

    name: []const u8,
};

/// Attempt to detect the presence of a device, given a devicetree
/// node that might describe it. The return value, if present, is
/// private to the device and must be passed in to the attach, detach,
/// and query functions.
pub const DetectFn = *const fn (allocator: *Allocator, devicenode: *Node) Error!*Driver;

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

/// TBD not sure how this should work just yet.
pub const QueryFn = *const fn (device: *Device) Error!void;

// ----------------------------------------------------------------------
// Utilities
// ----------------------------------------------------------------------
