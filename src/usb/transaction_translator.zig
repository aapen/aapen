const device = @import("device.zig");
const Device = device.Device;

pub const TransactionTranslator = struct {
    hub: ?*Device = null, // the nearest upstream high speed hub
    think_time: u32 = 0, // think time when starting split
};
