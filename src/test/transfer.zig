const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const device = @import("../usb/device.zig");
const transfer = @import("../usb/transfer.zig");

pub fn testBody() !void {
    // these tests all relied on a state machine implementation that
    // used to be in Transfer structs.
    //
    // at some point I expect to re-introduce the state machine to
    // clarify behavior that is currently muddled in drivers/dwc_otg_usb.zig
    // and the interrupt handler in drivers/dwc/channel.zig
}
