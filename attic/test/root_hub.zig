const std = @import("std");
const root = @import("root");

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectEqualSlices = helpers.expectEqualSlices;
const expectError = helpers.expectError;

const usb = @import("../usb.zig");

const reg = @import("../drivers/dwc/registers.zig");
const HostPortStatusAndControl = reg.HostPortStatusAndControl;
const HostRegisters = reg.HostRegisters;

const RootHub = @import("../drivers/dwc/root_hub.zig");

var g_buffer: [512]u8 = undefined;

pub fn testBody() !void {
    try getDeviceDescriptor();
    try getDeviceDescriptorShortBuffer();
    try getConfigurationDescriptor();
    try getConfigurationDescriptorShortBuffer();
    try getStringDescriptors();
    try getStatus();
    try setConfiguration();
    try getConfiguration();
    try getDescriptor();
    try getHubStatus();
    try getPortStatus();
    try setPortFeature();
    try setAddress();
    try setHubFeature();
    try clearHubFeature();
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

fn control(setup: usb.SetupPacket, data: ?[]u8) usb.URB.Status {
    var regs: HostRegisters = fakeRegisters();
    var hub: RootHub = .{};
    hub.init(&regs);
    return hub.control(@constCast(&setup), data);
}

const RequestTarget = enum { Standard, Class };

fn descriptorTransfer(trg: RequestTarget, descriptor_type: u8, descriptor_index: u8, index: u16, data_buffer: []u8) usb.URB.Status {
    return control(.{
        .request = usb.USB_REQUEST_GET_DESCRIPTOR,
        .request_type = switch (trg) {
            .Standard => usb.USB_REQUEST_TYPE_DEVICE_STANDARD_IN,
            .Class => usb.USB_REQUEST_TYPE_DEVICE_CLASS_IN,
        },
        .value = @as(u16, descriptor_type) << 8 | @as(u8, descriptor_index),
        .index = index,
        .data_size = @truncate(data_buffer.len),
    }, data_buffer);
}

fn deviceDescriptorTransfer(descriptor_index: u8, lang_id: u16, data_buffer: []u8) usb.URB.Status {
    return descriptorTransfer(.Standard, usb.USB_DESCRIPTOR_TYPE_DEVICE, descriptor_index, lang_id, data_buffer);
}

fn configurationDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) usb.URB.Status {
    return descriptorTransfer(.Standard, usb.USB_DESCRIPTOR_TYPE_CONFIGURATION, descriptor_index, 0, data_buffer);
}

fn setAddressTransfer(device_address: usb.DeviceAddress) usb.URB.Status {
    return control(.{
        .request = usb.USB_REQUEST_SET_ADDRESS,
        .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT,
        .value = device_address,
        .index = 0,
        .data_size = 0,
    }, null);
}

fn getHubDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) usb.URB.Status {
    return descriptorTransfer(.Class, usb.USB_DESCRIPTOR_TYPE_HUB, descriptor_index, 0, data_buffer);
}

fn setConfigurationTransfer(config: u16) usb.URB.Status {
    return control(.{
        .request = usb.USB_REQUEST_SET_CONFIGURATION,
        .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT,
        .value = config,
        .index = 0,
        .data_size = 0,
    }, null);
}

fn getConfigurationTransfer(data_buffer: []u8) usb.URB.Status {
    return control(.{
        .request = usb.USB_REQUEST_GET_CONFIGURATION,
        .request_type = usb.USB_REQUEST_TYPE_DEVICE_STANDARD_IN,
        .value = 0,
        .index = 0,
        .data_size = 1,
    }, data_buffer);
}

fn getStatusTransfer(trg: RequestTarget, data_buffer: []u8) usb.URB.Status {
    return control(.{
        .request = usb.USB_REQUEST_GET_STATUS,
        .request_type = switch (trg) {
            .Standard => usb.USB_REQUEST_TYPE_DEVICE_STANDARD_IN,
            .Class => usb.USB_REQUEST_TYPE_DEVICE_CLASS_IN,
        },
        .value = 0,
        .index = 0,
        .data_size = @truncate(data_buffer.len),
    }, data_buffer);
}

fn getHubPortStatusTransfer(port_number: u8, data_buffer: []u8) usb.URB.Status {
    return control(.{
        .request = usb.USB_REQUEST_GET_STATUS,
        .request_type = usb.USB_REQUEST_TYPE_OTHER_CLASS_IN,
        .value = 0,
        .index = port_number,
        .data_size = 4,
    }, data_buffer);
}

fn setHubPortFeatureTransfer(feature: u16, port_number: u8, port_indicator: u8) usb.URB.Status {
    const index: u16 = @as(u16, port_indicator) | port_number;

    return control(.{
        .request = usb.USB_REQUEST_SET_FEATURE,
        .request_type = usb.USB_REQUEST_TYPE_OTHER_CLASS_OUT,
        .value = feature,
        .index = index,
        .data_size = 0,
    }, null);
}

fn hubFeatureTransfer(req: u8, feature: u16) usb.URB.Status {
    return control(.{
        .request = req,
        .request_type = usb.USB_REQUEST_TYPE_DEVICE_CLASS_OUT,
        .value = feature,
        .index = 0,
        .data_size = 0,
    }, null);
}

fn setHubFeatureTransfer(feature: u16) usb.URB.Status {
    return hubFeatureTransfer(usb.USB_REQUEST_SET_FEATURE, feature);
}

fn clearHubFeatureTransfer(feature: u16) usb.URB.Status {
    return hubFeatureTransfer(usb.USB_REQUEST_CLEAR_FEATURE, feature);
}

fn getDeviceDescriptor() !void {
    const buffer_size = usb.DeviceDescriptor.STANDARD_LENGTH;

    expectEqual(@src(), usb.URB.Status.OK, deviceDescriptorTransfer(0, 0, g_buffer[0..buffer_size]));
    const device_descriptor: *usb.DeviceDescriptor = @ptrCast(@alignCast(&g_buffer));

    expectEqual(@src(), usb.DeviceDescriptor{
        .length = usb.DeviceDescriptor.STANDARD_LENGTH,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_DEVICE,
        .usb_standard_compliance = 0x200,
        .device_class = usb.USB_DEVICE_HUB,
        .device_subclass = 0,
        .device_protocol = usb.USB_HUB_PROTOCOL_HIGH_SPEED_SINGLE_TT,
        .max_packet_size = 64,
        .vendor = 0x1209,
        .product = 0x0007,
        .device_release = 0x0100,
        .manufacturer_name = 3,
        .product_name = 2,
        .serial_number = 1,
        .configuration_count = 1,
    }, device_descriptor.*);
}

fn getDeviceDescriptorShortBuffer() !void {
    const short_buffer_len: u16 = usb.DeviceDescriptor.STANDARD_LENGTH / 2;
    expectEqual(@src(), usb.URB.Status.OK, deviceDescriptorTransfer(0, 0, g_buffer[0..short_buffer_len]));
}

fn getConfigurationDescriptor() !void {
    const buffer_size = usb.ConfigurationDescriptor.STANDARD_LENGTH + usb.InterfaceDescriptor.STANDARD_LENGTH + usb.EndpointDescriptor.STANDARD_LENGTH;
    expectEqual(@src(), usb.URB.Status.OK, configurationDescriptorTransfer(1, g_buffer[0..buffer_size]));
}

fn getConfigurationDescriptorShortBuffer() !void {
    const buffer_size = (usb.ConfigurationDescriptor.STANDARD_LENGTH + usb.InterfaceDescriptor.STANDARD_LENGTH + usb.EndpointDescriptor.STANDARD_LENGTH) / 2;
    expectEqual(@src(), usb.URB.Status.OK, configurationDescriptorTransfer(1, g_buffer[0..buffer_size]));
}

fn stringDescriptorTransfer(descriptor_index: u8, lang_id: u16) *align(2) usb.StringDescriptor {
    const buffer_size = @sizeOf(usb.StringDescriptor);
    const status = descriptorTransfer(.Standard, usb.USB_DESCRIPTOR_TYPE_STRING, descriptor_index, lang_id, g_buffer[0..buffer_size]);
    expectEqual(@src(), usb.URB.Status.OK, status);
    return @ptrCast(@alignCast(&g_buffer));
}

fn getStringDescriptors() !void {
    // Should be a descriptor header plus a single u16
    const string = stringDescriptorTransfer(0, usb.USB_LANGID_NONE);
    expectEqualSlices(@src(), u16, &.{0x0409}, string.body[0..1]);

    // check string at index 2
    const string2 = stringDescriptorTransfer(2, usb.USB_LANGID_NONE);
    const str_slice = try string2.asSlice(helpers.allocator);
    defer helpers.allocator.free(str_slice);

    expectEqualSlices(@src(), u8, "Aapen USB", str_slice[0..9]);
}

fn getStatus() !void {
    expectEqual(@src(), usb.URB.Status.OK, getStatusTransfer(.Standard, g_buffer[0..2]));
}

fn setConfiguration() !void {
    expectEqual(@src(), usb.URB.Status.OK, setConfigurationTransfer(1));
    expectEqual(@src(), usb.URB.Status.OK, setConfigurationTransfer(99));
}

fn getConfiguration() !void {
    expectEqual(@src(), usb.URB.Status.OK, getConfigurationTransfer(g_buffer[0..1]));
    expectEqual(@src(), @as(u8, 1), g_buffer[0]);
}

fn getDescriptor() !void {
    expectEqual(@src(), usb.URB.Status.OK, getHubDescriptorTransfer(1, g_buffer[0..usb.HubDescriptor.STANDARD_LENGTH]));

    const hub_descriptor: *usb.HubDescriptor = @ptrCast(@alignCast(&g_buffer));
    expectEqual(@src(), usb.USB_DESCRIPTOR_TYPE_HUB, hub_descriptor.descriptor_type);
    expectEqual(@src(), @as(u8, 1), hub_descriptor.number_ports);
}

fn getHubStatus() !void {
    expectEqual(@src(), usb.URB.Status.OK, getStatusTransfer(.Class, g_buffer[0..4]));
}

fn getPortStatus() !void {
    expectEqual(@src(), usb.URB.Status.OK, getHubPortStatusTransfer(1, g_buffer[0..4]));
}

fn setPortFeature() !void {
    expectEqual(@src(), usb.URB.Status.OK, setHubPortFeatureTransfer(usb.HUB_PORT_FEATURE_PORT_POWER, 1, 0));
}

fn setAddress() !void {
    expectEqual(@src(), usb.URB.Status.OK, setAddressTransfer(1));
}

fn setHubFeature() !void {
    expectEqual(@src(), usb.URB.Status.OK, setHubFeatureTransfer(usb.USB_HUB_FEATURE_C_LOCAL_POWER));
}

fn clearHubFeature() !void {
    expectEqual(@src(), usb.URB.Status.OK, clearHubFeatureTransfer(usb.USB_HUB_FEATURE_C_LOCAL_POWER));
}
