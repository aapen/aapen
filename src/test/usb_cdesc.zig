const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const usb = @import("../usb.zig");
const Device = usb.Device;
const DeviceConfiguration = usb.DeviceConfiguration;
const TransferType = usb.TransferType;

const root_hub = @import("../drivers/dwc/root_hub.zig");

pub fn testBody() !void {
    const allocator = root.kernel_allocator;

    try parseHubConfiguration(allocator);
    try parseQemuKeyboardConfiguration(allocator);
}

fn parseHubConfiguration(allocator: Allocator) !void {
    _ = root.printf("parseHubConfiguration\n");

    const as_bytes = [_]u8{
        0x09, 0x02, 0x20, 0x00, 0x01, 0x01, 0x00, 0xc0, 0x01, 0x09, 0x04, 0x00, 0x00, 0x01, 0x09, 0x00,
        0x01, 0x00, 0x07, 0x05, 0x81, 0x03, 0x04, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };

    const dev = try DeviceConfiguration.initFromBytes(allocator, &as_bytes);

    expectEqual(@as(u8, 1), dev.configuration_descriptor.interface_count);
    expect(dev.interfaces[0] != null);
    expectEqual(@as(u8, 1), dev.interfaces[0].?.endpoint_count);
    expect(dev.endpoints[0][0] != null);
    expectEqual(@as(u8, 0x81), dev.endpoints[0][0].?.endpoint_address);
    expectEqual(TransferType.interrupt, dev.endpoints[0][0].?.attributes.endpoint_type);
}

fn parseQemuKeyboardConfiguration(allocator: Allocator) !void {
    _ = root.printf("parseQemuKeyboardConfiguration\n");

    const as_bytes = [_]u8{
        0x09, 0x02, 0x22, 0x00, 0x01, 0x01, 0x08, 0xa0, 0x32, 0x09, 0x04, 0x00, 0x00, 0x01, 0x03, 0x01,
        0x01, 0x00, 0x09, 0x21, 0x11, 0x01, 0x00, 0x01, 0x22, 0x3f, 0x00, 0x07, 0x05, 0x81, 0x03, 0x08,
        0x00, 0x0a,
    };

    const dev = try DeviceConfiguration.initFromBytes(allocator, &as_bytes);

    expectEqual(@as(u8, 1), dev.configuration_descriptor.interface_count);
}
