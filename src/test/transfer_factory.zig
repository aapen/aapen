const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const usb = @import("../usb.zig");
const DescriptorType = usb.DescriptorType;
const LangID = usb.LangID;
const StandardDeviceRequests = usb.StandardDeviceRequests;
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

pub fn testBody() !void {
    descriptorQuery();
    deviceDescriptor();
}

fn descriptorQuery() void {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initDescriptorTransfer(DescriptorType.device, 0, 0, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn deviceDescriptor() void {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initDeviceDescriptorTransfer(0, 0, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn configurationDescriptor() void {
    const buffer_size = 2;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initConfigurationDescriptorTransfer(0, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn stringDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initStringDescriptorTransfer(0, LangID.none, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn interfaceDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initInterfaceDescriptorTransfer(0, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn endpointDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initEndpointDescriptorTransfer(0, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn hubDescriptor() void {
    const buffer_size = @sizeOf(StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initGetHubDescriptorTransfer(0, &buffer);
    expectEqual(TransferType.control, xfer.endpoint_type);
    expectEqual(StandardDeviceRequests.get_descriptor, xfer.setup.request);
}

fn interruptTransfer() void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initInterruptTransfer(&buffer);
    expectEqual(TransferType.interrupt, xfer.endpoint_type);
}
