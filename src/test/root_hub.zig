const std = @import("std");
const root = @import("root");

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectEqualSlices = helpers.expectEqualSlices;
const expectError = helpers.expectError;

const usb = @import("../usb.zig");
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DeviceConfiguration = usb.DeviceConfiguration;
const DeviceDescriptor = usb.DeviceDescriptor;
const EndpointDescriptor = usb.EndpointDescriptor;
const HubDescriptor = usb.HubDescriptor;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const LangID = usb.LangID;
const PortStatus = usb.PortStatus;
const StringDescriptor = usb.StringDescriptor;
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferCompletionStatus = usb.TransferRequest.CompletionStatus;
const TransferType = usb.TransferType;

const reg = @import("../drivers/dwc/registers.zig");
const HostPortStatusAndControl = reg.HostPortStatusAndControl;
const HostRegisters = reg.HostRegisters;

const RootHub = @import("../drivers/dwc/root_hub.zig");

pub fn testBody() !void {
    try supportedTransferTypes();
    try getDeviceDescriptor();
    try getDeviceDescriptorShortBuffer();
    try getConfigurationDescriptor();
    try getConfigurationDescriptorShortBuffer();
    try getStringDescriptors();
    try getStringDescriptorShortBuffer();
    try getStatus();
    try setConfiguration();
    try getConfiguration();
    try getDescriptor();
    try getHubStatus();
    try getPortStatus();
    try setPortFeature();
    try setPortFeatureReset();
    try setAddress();
    try setHubFeature();
    try clearHubFeature();
    try hubHoldInterruptRequestUntilChange();
}

fn fakeRegisters() reg.HostRegisters {
    const u32zero = @as(u32, 0);
    return .{
        .config = @bitCast(u32zero),
        .frame_interval = @bitCast(u32zero),
        .frame_num = @bitCast(u32zero),
        .host_fifo_status = @bitCast(u32zero),
        ._unused_padding_1 = [_]u32{0} ** 8,
        .port = @bitCast(u32zero),
    };
}

fn expectTransferCompletionStatus(expected_status: TransferCompletionStatus, xfer: *TransferRequest) void {
    var regs: HostRegisters = fakeRegisters();
    var hub: RootHub = .{};
    hub.init(&regs);

    hub.hubHandleTransfer(xfer);
    expectEqual(@src(), expected_status, xfer.status);
}

fn supportedTransferTypes() !void {
    var endpoint_iso: EndpointDescriptor = .{
        .length = EndpointDescriptor.STANDARD_LENGTH,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_ENDPOINT,
        .endpoint_address = 0,
        .attributes = TransferType.isochronous,
        .max_packet_size = 8,
        .interval = 1,
    };
    var data: [*]u8 = &[_]u8{};

    var iso: TransferRequest = .{
        .endpoint_desc = &endpoint_iso,
        .setup_data = undefined,
        .data = data,
    };

    var endpoint_bulk: EndpointDescriptor = .{
        .length = EndpointDescriptor.STANDARD_LENGTH,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_ENDPOINT,
        .endpoint_address = 0,
        .attributes = TransferType.bulk,
        .max_packet_size = 8,
        .interval = 1,
    };
    var bulk: TransferRequest = .{
        .endpoint_desc = &endpoint_bulk,
        .setup_data = undefined,
        .data = data,
    };

    expectTransferCompletionStatus(.unsupported_request, &iso);
    expectTransferCompletionStatus(.unsupported_request, &bulk);
}

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

fn descriptorTransfer(descriptor_type: u8, descriptor_index: u8, index: u16, data_buffer: []u8) TransferRequest {
    const length: u16 = @truncate(data_buffer.len);
    const val: u16 = @as(u16, descriptor_type) << 8 | @as(u8, descriptor_index);
    return .{
        .device = &nulldev,
        .data = data_buffer.ptr,
        .size = @truncate(data_buffer.len),
        .setup_data = .{
            .request = usb.USB_REQUEST_GET_DESCRIPTOR,
            .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_IN,
            .value = val,
            .index = index,
            .data_size = length,
        },
    };
}

fn deviceDescriptorTransfer(descriptor_index: u8, lang_id: u16, data_buffer: []u8) TransferRequest {
    return descriptorTransfer(usb.USB_DESCRIPTOR_TYPE_DEVICE, descriptor_index, lang_id, data_buffer);
}

fn configurationDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) TransferRequest {
    return descriptorTransfer(usb.USB_DESCRIPTOR_TYPE_CONFIGURATION, descriptor_index, 0, data_buffer);
}

fn stringDescriptorTransfer(descriptor_index: u8, lang_id: u16, data_buffer: []u8) TransferRequest {
    return descriptorTransfer(usb.USB_DESCRIPTOR_TYPE_STRING, descriptor_index, lang_id, data_buffer);
}

fn setAddressTransfer(device_address: usb.DeviceAddress) TransferRequest {
    return .{
        .device = &nulldev,
        .data = @ptrFromInt(0),
        .size = 0,
        .setup_data = .{
            .request = usb.USB_REQUEST_SET_ADDRESS,
            .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT,
            .value = device_address,
            .index = 0,
            .data_size = 0,
        },
    };
}

fn getHubDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) TransferRequest {
    var t = descriptorTransfer(usb.USB_DESCRIPTOR_TYPE_HUB, descriptor_index, 0, data_buffer);
    t.setup_data.request_type = usb.USB_REQUEST_TYPE_DEVICE_CLASS_IN;
    return t;
}

fn setConfigurationTransfer(config: u16) TransferRequest {
    return .{
        .device = &nulldev,
        .data = @ptrFromInt(0),
        .size = 0,
        .setup_data = .{
            .request = usb.USB_REQUEST_SET_CONFIGURATION,
            .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT,
            .value = config,
            .index = 0,
            .data_size = 0,
        },
    };
}

fn getConfigurationTransfer(data_buffer: []u8) TransferRequest {
    return .{
        .device = &nulldev,
        .data = data_buffer.ptr,
        .size = @truncate(data_buffer.len),
        .setup_data = .{
            .request = usb.USB_REQUEST_GET_CONFIGURATION,
            .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_IN,
            .value = 0,
            .index = 0,
            .data_size = 1,
        },
    };
}

fn getStatusTransfer(data_buffer: []u8) TransferRequest {
    const length: u16 = @truncate(data_buffer.len);
    return .{
        .device = &nulldev,
        .data = data_buffer.ptr,
        .size = @truncate(data_buffer.len),
        .setup_data = .{
            .request = usb.USB_REQUEST_GET_STATUS,
            .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_IN,
            .value = 0,
            .index = 0,
            .data_size = length,
        },
    };
}

fn getHubStatusTransfer(data_buffer: []u8) TransferRequest {
    var t = getStatusTransfer(data_buffer);
    t.setup_data.request_type = usb.USB_REQUEST_TYPE_DEVICE_CLASS_IN;
    return t;
}

fn getHubPortStatusTransfer(port_number: u8, data_buffer: []u8) TransferRequest {
    return .{
        .device = &nulldev,
        .data = data_buffer.ptr,
        .size = @truncate(data_buffer.len),
        .setup_data = .{
            .request = usb.USB_REQUEST_GET_STATUS,
            .request_type = usb.USB_REQUEST_TYPE_OTHER_CLASS_IN,
            .value = 0,
            .index = port_number,
            .data_size = 4,
        },
    };
}

fn setHubPortFeatureTransfer(feature: u16, port_number: u8, port_indicator: u8) TransferRequest {
    const index: u16 = @as(u16, port_indicator) | port_number;
    return .{
        .device = &nulldev,
        .data = @ptrFromInt(0),
        .size = 0,
        .setup_data = .{
            .request = usb.USB_REQUEST_SET_FEATURE,
            .request_type = usb.USB_REQUEST_TYPE_OTHER_CLASS_OUT,
            .value = feature,
            .index = index,
            .data_size = 0,
        },
    };
}

fn hubFeatureTransfer(req: u8, feature: u16) TransferRequest {
    return .{
        .device = &nulldev,
        .data = @ptrFromInt(0),
        .size = 0,
        .setup_data = .{
            .request = req,
            .request_type = usb.USB_REQUEST_TYPE_DEVICE_CLASS_OUT,
            .value = feature,
            .index = 0,
            .data_size = 0,
        },
    };
}

fn setHubFeatureTransfer(feature: u16) TransferRequest {
    return hubFeatureTransfer(usb.USB_REQUEST_SET_FEATURE, feature);
}

fn clearHubFeatureTransfer(feature: u16) TransferRequest {
    return hubFeatureTransfer(usb.USB_REQUEST_CLEAR_FEATURE, feature);
}

fn getDeviceDescriptor() !void {
    const buffer_size = @sizeOf(DeviceDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = deviceDescriptorTransfer(0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);

    const device_descriptor = std.mem.bytesAsValue(DeviceDescriptor, xfer.data[0..@sizeOf(DeviceDescriptor)]);

    expectEqual(@src(), usb.USB_DESCRIPTOR_TYPE_DEVICE, device_descriptor.descriptor_type);
    expectEqual(@src(), usb.USB_DEVICE_HUB, device_descriptor.device_class);
    expectEqual(@src(), @as(u8, 0), device_descriptor.device_subclass);
    expectEqual(@src(), @as(u8, 1), device_descriptor.device_protocol);
    expect(@src(), device_descriptor.configuration_count >= 1);
    expect(@src(), device_descriptor.max_packet_size >= 8);
}

fn getDeviceDescriptorShortBuffer() !void {
    const short_buffer_len: u16 = @as(u16, @sizeOf(DeviceDescriptor)) / 2;
    var buffer: [short_buffer_len]u8 = undefined;

    var xfer = deviceDescriptorTransfer(0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(u19, short_buffer_len), xfer.actual_size);
}

fn getConfigurationDescriptor() !void {
    const buffer_size = ConfigurationDescriptor.STANDARD_LENGTH + InterfaceDescriptor.STANDARD_LENGTH + EndpointDescriptor.STANDARD_LENGTH;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = configurationDescriptorTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);

    var config = try DeviceConfiguration.initFromBytes(helpers.allocator, &buffer);
    defer {
        config.deinit();
        helpers.allocator.destroy(config);
    }

    expectEqual(@src(), usb.USB_DESCRIPTOR_TYPE_CONFIGURATION, config.configuration_descriptor.descriptor_type);
    expect(@src(), config.configuration_descriptor.interface_count >= 1);

    expectEqual(@src(), usb.USB_DESCRIPTOR_TYPE_INTERFACE, config.interfaces[0].?.descriptor_type);
    expectEqual(@src(), usb.USB_INTERFACE_CLASS_HUB, config.interfaces[0].?.interface_class);
    expect(@src(), config.interfaces[0].?.endpoint_count >= 1);

    expectEqual(@src(), usb.USB_DESCRIPTOR_TYPE_ENDPOINT, config.endpoints[0][0].?.descriptor_type);
    expect(@src(), config.endpoints[0][0].?.max_packet_size >= 4);
}

fn getConfigurationDescriptorShortBuffer() !void {
    const buffer_size = (@sizeOf(ConfigurationDescriptor) + @sizeOf(InterfaceDescriptor) + @sizeOf(EndpointDescriptor)) / 2;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = configurationDescriptorTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getStringDescriptors() !void {
    // Should be a descriptor header plus a single u16
    const buffer_size = @sizeOf(usb.StringDescriptor);
    var buffer: [buffer_size]u8 align(2) = undefined;

    var xfer = stringDescriptorTransfer(0, usb.USB_LANGID_NONE, &buffer);
    expectTransferCompletionStatus(.ok, &xfer);

    const string = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data[0..buffer_size])));

    expectEqualSlices(@src(), u16, &.{0x0409}, string.body[0..1]);

    // check string at index 2
    xfer = stringDescriptorTransfer(2, usb.USB_LANGID_NONE, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    const string2 = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data[0..buffer_size])));
    const str_slice = try string2.asSlice(helpers.allocator);
    defer helpers.allocator.free(str_slice);

    expectEqualSlices(@src(), u8, "Aapen USB", str_slice[0..9]);
}

fn getStringDescriptorShortBuffer() !void {
    const buffer_size = 6;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = stringDescriptorTransfer(1, usb.USB_LANGID_NONE, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getStatus() !void {
    const buffer_size = @sizeOf(u16);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = getStatusTransfer(&buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setConfiguration() !void {
    var xfer = setConfigurationTransfer(1);
    expectTransferCompletionStatus(.ok, &xfer);

    var xfer2 = setConfigurationTransfer(99);
    expectTransferCompletionStatus(.ok, &xfer2);
}

fn getConfiguration() !void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = getConfigurationTransfer(&buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(u8, buffer_size), xfer.data[0]);
}

fn getDescriptor() !void {
    const buffer_size = @sizeOf(HubDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = getHubDescriptorTransfer(0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);

    const hub_descriptor = std.mem.bytesAsValue(HubDescriptor, xfer.data[0..@sizeOf(HubDescriptor)]);

    expectEqual(@src(), usb.USB_DESCRIPTOR_TYPE_HUB, hub_descriptor.descriptor_type);
    expectEqual(@src(), @as(u8, 1), hub_descriptor.number_ports);
}

fn getHubStatus() !void {
    const buffer_size = 4;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = getHubStatusTransfer(&buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getPortStatus() !void {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = getHubPortStatusTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getPortPowerStatus() !bool {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = getHubPortStatusTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);

    const port_status = std.mem.bytesAsValue(PortStatus, xfer.data[0..@sizeOf(PortStatus)]);

    return port_status.port_status.power == 1;
}

fn setPortFeature() !void {
    const buffer_size = 0;

    var xfer = setHubPortFeatureTransfer(usb.HUB_PORT_FEATURE_PORT_POWER, 1, 0);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setPortFeatureReset() !void {
    const buffer_size = 0;

    var xfer = setHubPortFeatureTransfer(usb.HUB_PORT_FEATURE_PORT_RESET, 1, 0);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@src(), @as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setAddress() !void {
    var xfer = setAddressTransfer(1);

    expectTransferCompletionStatus(.ok, &xfer);
}

fn setHubFeature() !void {
    var xfer = setHubFeatureTransfer(usb.USB_HUB_FEATURE_C_LOCAL_POWER);
    expectTransferCompletionStatus(.unsupported_request, &xfer);
}

fn clearHubFeature() !void {
    var xfer = clearHubFeatureTransfer(usb.USB_HUB_FEATURE_C_LOCAL_POWER);
    expectTransferCompletionStatus(.unsupported_request, &xfer);
}

fn hubHoldInterruptRequestUntilChange() !void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    var xfer = TransferRequest.initInterrupt(&nulldev, &buffer);
    expectTransferCompletionStatus(.incomplete, &xfer);
}
