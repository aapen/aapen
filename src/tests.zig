const std = @import("std");
pub const schedule = @import("schedule.zig");
pub const usb_descriptor = @import("usb/descriptor.zig");
pub const root_hub = @import("drivers/dwc/root_hub.zig");

test "parent of all tests" {
    std.debug.print("\n", .{});

    std.testing.refAllDecls(@This());
}
