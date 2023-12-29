const std = @import("std");
pub const bcd = @import("bcd.zig");
pub const forty_stack = @import("forty/stack.zig");
pub const root_hub = @import("drivers/dwc/root_hub.zig");

test "parent of all tests" {
    std.debug.print("\n", .{});

    std.testing.refAllDecls(@This());
}
