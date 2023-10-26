const std = @import("std");
const Allocator = std.mem.Allocator;

const devicetree = @import("devicetree.zig");

pub const interfaces = @import("hal/interfaces.zig");
pub const detect = @import("hal/detect.zig");

pub var dma_controller: *interfaces.DMAController = undefined;
pub var interrupt_controller: *interfaces.InterruptController = undefined;
pub var timer: *interfaces.Timer = undefined;
pub var usb: *interfaces.USB = undefined;
pub var video_controller: *interfaces.VideoController = undefined;

pub fn init(root: *devicetree.Fdt.Node, allocator: *Allocator) !void {
    try detect.detectAndInit(root, allocator);
}
