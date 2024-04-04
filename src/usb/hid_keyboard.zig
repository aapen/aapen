/// Protocol definition for USB HID devices
///
/// See USB Device Class Definition for Human Interface Devices
/// Revision 1.1
const std = @import("std");

const log = std.log.scoped(.usb_hid_keyboard);

const root = @import("root");
const delayMillis = root.HAL.delayMillis;

const descriptor = @import("descriptor.zig");
const HidDescriptor = descriptor.HidDescriptor;
const InterfaceDescriptor = descriptor.InterfaceDescriptor;

const device = @import("device.zig");
const Device = device.Device;
const DeviceClass = device.DeviceClass;
const DeviceDriver = device.DeviceDriver;
const HidProtocol = device.HidProtocol;

const Error = @import("status.zig").Error;

fn isKeyboard(iface: *InterfaceDescriptor) bool {
    return iface.isHid() and
        iface.interface_protocol == HidProtocol.keyboard and
        (iface.interface_subclass == 0 or iface.interface_subclass == 1);
}

pub fn hidKeyboardDriverCanBind(dev: *Device) bool {
    const configuration = dev.configuration;

    for (0..configuration.configuration_descriptor.interface_count) |iface_num| {
        const iface = configuration.interfaces[iface_num];
        if (iface != null and isKeyboard(iface.?)) {
            return true;
        }
    }

    return false;
}

pub fn hidKeyboardDriverDeviceBind(dev: *Device) Error!void {
    log.debug("hid keyboard driver pretending to bind device {d}", .{dev.address});
}

pub fn hidKeyboardDriverDeviceUnbind(dev: *Device) void {
    log.debug("hid keyboard driver pretending to unbind device {d}", .{dev.address});
}

pub const driver: DeviceDriver = .{
    .name = "USB Keyboard",
    .canBind = hidKeyboardDriverCanBind,
    .bind = hidKeyboardDriverDeviceBind,
    .unbind = hidKeyboardDriverDeviceUnbind,
};
