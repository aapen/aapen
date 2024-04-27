const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const usb = @import("../usb.zig");
const StringDescriptor = usb.StringDescriptor;
const TransferType = usb.TransferType;

const transfer_factory = @import("../usb/transfer_factory.zig");
const initDescriptorTransfer = transfer_factory.initDescriptorTransfer;
const initDeviceDescriptorTransfer = transfer_factory.initDeviceDescriptorTransfer;
const initConfigurationDescriptorTransfer = transfer_factory.initConfigurationDescriptorTransfer;
const initStringDescriptorTransfer = transfer_factory.initStringDescriptorTransfer;
const initInterfaceDescriptorTransfer = transfer_factory.initInterfaceDescriptorTransfer;
const initEndpointDescriptorTransfer = transfer_factory.initEndpointDescriptorTransfer;
const initGetHubDescriptorTransfer = transfer_factory.initGetHubDescriptorTransfer;
const initInterruptTransfer = transfer_factory.initInterruptTransfer;

var nulldev: usb.Device = .{
    .address = 0,
    .speed = usb.UsbSpeed.High,
    .parent = null,
    .parent_port = 0,
    .tt = null,
    .device_descriptor = undefined,
    .configuration = undefined,
    .product = @constCast("nothing"),
    .state = usb.DeviceState.attached,
    .driver = null,
    .driver_private = undefined,
};

pub fn testBody() !void {
    descriptorQuery();
    deviceDescriptor();
}

fn descriptorQuery() void {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initDescriptorTransfer(&nulldev, usb.USB_DESCRIPTOR_TYPE_DEVICE, 0, 0, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn deviceDescriptor() void {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initDeviceDescriptorTransfer(&nulldev, 0, 0, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn configurationDescriptor() void {
    const buffer_size = 2;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initConfigurationDescriptorTransfer(&nulldev, 0, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn stringDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initStringDescriptorTransfer(&nulldev, 0, usb.USB_LANGID_NONE, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn interfaceDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initInterfaceDescriptorTransfer(&nulldev, 0, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn endpointDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initEndpointDescriptorTransfer(&nulldev, 0, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn hubDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initGetHubDescriptorTransfer(&nulldev, 0, &buffer);
    expect(@src(), xfer.isControlRequest());
    expectEqual(@src(), usb.USB_REQUEST_GET_DESCRIPTOR, xfer.setup_data.request);
}

fn interruptTransfer() void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initInterruptTransfer(&nulldev, &buffer);
    expectEqual(@src(), TransferType.interrupt, xfer.endpoint_type);
}
