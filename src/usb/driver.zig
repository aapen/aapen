//const Device = @import("device.zig").Device;
const Error = @import("status.zig").Error;

pub const DeviceDriver = struct {
    name: []const u8,
    // bind: *const fn (device: *Device) Error!void,
    // unbind: *const fn (device: *Device) Error!void,
};
