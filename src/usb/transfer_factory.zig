const std = @import("std");
const log = std.log.scoped(.usb);

const descriptor = @import("descriptor.zig");
const DescriptorType = descriptor.DescriptorType;

const device = @import("device.zig");
const DeviceAddress = device.DeviceAddress;
const StandardDeviceRequests = device.StandardDeviceRequests;

const hub = @import("hub.zig");
const HubClassRequest = hub.ClassRequest;
const HubFeature = hub.HubFeature;
const PortFeature = hub.PortFeature;

const language = @import("language.zig");
const LangID = language.LangID;

const request = @import("request.zig");
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;

const transfer = @import("transfer.zig");
const Transfer = transfer.Transfer;
const TransferType = transfer.TransferType;
const SetupPacket = transfer.SetupPacket;

/// Create various Transfer instances with a goal-oriented API
pub fn initInterruptTransfer(data_buffer: []u8) Transfer {
    return Transfer.initInterrupt(data_buffer);
}

pub fn initControlTransfer(setup_packet: SetupPacket, data_buffer: []u8) Transfer {
    return Transfer.initControl(setup_packet, @constCast(data_buffer));
}

pub fn initDescriptorTransfer(descriptor_type: DescriptorType, descriptor_index: u8, lang_id: u16, data_buffer: []u8) Transfer {
    const length: u16 = @truncate(data_buffer.len);
    const val: u16 = @as(u16, @intFromEnum(descriptor_type)) << 8 | @as(u8, descriptor_index);
    const setup_packet = SetupPacket.init(.device, .standard, .device_to_host, @intFromEnum(StandardDeviceRequests.get_descriptor), val, lang_id, length);

    return initControlTransfer(setup_packet, data_buffer);
}

pub fn initDeviceDescriptorTransfer(descriptor_index: u8, lang_id: u16, data_buffer: []u8) Transfer {
    return initDescriptorTransfer(.device, descriptor_index, lang_id, data_buffer);
}

pub fn initConfigurationDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) Transfer {
    return initDescriptorTransfer(.configuration, descriptor_index, 0, data_buffer);
}

pub fn initStringDescriptorTransfer(descriptor_index: u8, lang_id: LangID, data_buffer: []u8) Transfer {
    return initDescriptorTransfer(.string, descriptor_index, @intFromEnum(lang_id), data_buffer);
}

pub fn initInterfaceDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) Transfer {
    return initDescriptorTransfer(.interface, descriptor_index, 0, data_buffer);
}

pub fn initEndpointDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) Transfer {
    return initDescriptorTransfer(.endpoint, descriptor_index, 0, data_buffer);
}

pub fn initSetAddressTransfer(device_address: DeviceAddress) Transfer {
    const setup_packet = SetupPacket.init(.device, .standard, .host_to_device, @intFromEnum(StandardDeviceRequests.set_address), device_address, 0, 0);
    return initControlTransfer(setup_packet, &.{});
}

pub fn initGetStatusTransfer(data_buffer: []u8) Transfer {
    const length: u16 = @truncate(data_buffer.len);
    const setup_packet = SetupPacket.init(.device, .standard, .device_to_host, @intFromEnum(StandardDeviceRequests.get_status), 0, 0, length);
    return initControlTransfer(setup_packet, data_buffer);
}

pub fn initSetConfigurationTransfer(config: u16) Transfer {
    const setup_packet = SetupPacket.init(.device, .standard, .host_to_device, @intFromEnum(StandardDeviceRequests.set_configuration), config, 0, 0);
    return initControlTransfer(setup_packet, &.{});
}

pub fn initGetConfigurationTransfer(data_buffer: []u8) Transfer {
    const setup_packet = SetupPacket.init(.device, .standard, .device_to_host, @intFromEnum(StandardDeviceRequests.get_configuration), 0, 0, 1);
    return initControlTransfer(setup_packet, data_buffer);
}

pub fn initGetHubDescriptorTransfer(descriptor_index: u8, data_buffer: []u8) Transfer {
    const length: u16 = @truncate(data_buffer.len);
    const val: u16 = @as(u16, @intFromEnum(DescriptorType.hub)) << 8 | @as(u8, descriptor_index);
    const setup_packet = SetupPacket.init(.device, .class, .device_to_host, @intFromEnum(StandardDeviceRequests.get_descriptor), val, 0, length);
    return initControlTransfer(setup_packet, data_buffer);
}

pub fn initGetHubStatusTransfer(data_buffer: []u8) Transfer {
    const setup_packet = SetupPacket.init(.device, .class, .device_to_host, @intFromEnum(HubClassRequest.get_status), 0, 0, 4);
    return initControlTransfer(setup_packet, data_buffer);
}

pub fn initHubSetHubFeatureTransfer(feature: HubFeature) Transfer {
    const setup_packet = SetupPacket.init(.device, .class, .host_to_device, @intFromEnum(HubClassRequest.set_feature), @intFromEnum(feature), 0, 0);
    return initControlTransfer(setup_packet, &.{});
}

pub fn initHubClearHubFeatureTransfer(feature: HubFeature) Transfer {
    const setup_packet = SetupPacket.init(.device, .class, .host_to_device, @intFromEnum(HubClassRequest.clear_feature), @intFromEnum(feature), 0, 0);
    return initControlTransfer(setup_packet, &.{});
}

pub fn initHubGetPortStatusTransfer(port_number: u8, data_buffer: []u8) Transfer {
    const setup_packet = SetupPacket.init(.other, .class, .device_to_host, @intFromEnum(HubClassRequest.get_status), 0, port_number, 4);
    return initControlTransfer(setup_packet, data_buffer);
}

pub fn initHubSetPortFeatureTransfer(feature: PortFeature, port_number: u8, port_indicator: u8) Transfer {
    const index: u16 = @as(u16, port_indicator) | port_number;
    const setup_packet = SetupPacket.init(.other, .class, .host_to_device, @intFromEnum(HubClassRequest.set_feature), @intFromEnum(feature), index, 0);
    return initControlTransfer(setup_packet, &.{});
}

pub fn initHubClearPortFeatureTransfer(feature: PortFeature, port_number: u8) Transfer {
    const index: u16 = @as(u16, port_number);
    const setup_packet = SetupPacket.init(.other, .class, .host_to_device, @intFromEnum(HubClassRequest.clear_feature), @intFromEnum(feature), index, 0);
    return initControlTransfer(setup_packet, &.{});
}

// ----------------------------------------------------------------------
// Testing
// ----------------------------------------------------------------------

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "factory can create a transfer for a descriptor query" {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initDescriptorTransfer(.device, 0, 0, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create a specific transfer for a device descriptor query" {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initDeviceDescriptorTransfer(0, 0, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create a specific transfer for a configuration descriptor query" {
    const buffer_size = 2;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initConfigurationDescriptorTransfer(0, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create a specific transfer for a string descriptor query" {
    const buffer_size = @sizeOf(descriptor.StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initStringDescriptorTransfer(0, LangID.none, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create a specific transfer for an interface descriptor query" {
    const buffer_size = @sizeOf(descriptor.StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initInterfaceDescriptorTransfer(0, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create a specific transfer for an endpoint descriptor query" {
    const buffer_size = @sizeOf(descriptor.StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initEndpointDescriptorTransfer(0, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create a specific transfer for a hub descriptor query" {
    const buffer_size = @sizeOf(descriptor.StringDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initGetHubDescriptorTransfer(0, &buffer);
    try expectEqual(TransferType.control, xfer.endpoint_type);
    try expectEqual(@intFromEnum(StandardDeviceRequests.get_descriptor), xfer.setup.request);
}

test "factory can create an interrupt transfer" {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    const xfer = initInterruptTransfer(&buffer);
    try expectEqual(TransferType.interrupt, xfer.endpoint_type);
}
