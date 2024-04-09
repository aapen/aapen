const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");

const descriptor = @import("descriptor.zig");
const DescriptorType = descriptor.DescriptorType;

const device = @import("device.zig");
const Device = device.Device;
const DeviceAddress = device.DeviceAddress;
const StandardDeviceRequests = device.StandardDeviceRequests;

const hub = @import("hub.zig");
const HubClassRequest = hub.ClassRequest;

const language = @import("language.zig");
const LangID = language.LangID;

const request = @import("request.zig");
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;

const transfer = @import("transfer.zig");
const TransferRequest = transfer.TransferRequest;
const TransferType = transfer.TransferType;
const SetupPacket = transfer.SetupPacket;

/// Create various Transfer instances with a goal-oriented API
pub fn initInterruptTransfer(dev: *Device, data_buffer: []u8) TransferRequest {
    return TransferRequest.initInterrupt(dev, data_buffer);
}

pub fn initControlTransfer(dev: *Device, setup_packet: SetupPacket, data_buffer: []u8) TransferRequest {
    return TransferRequest.initControl(dev, setup_packet, @constCast(data_buffer));
}

pub fn initDescriptorTransfer(dev: *Device, descriptor_type: u8, descriptor_index: u8, lang_id: u16, data_buffer: []u8) TransferRequest {
    const length: u16 = @truncate(data_buffer.len);
    const val: u16 = @as(u16, descriptor_type) << 8 | @as(u8, descriptor_index);
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.device_to_host, StandardDeviceRequests.get_descriptor, val, lang_id, length);
    return initControlTransfer(dev, setup_packet, data_buffer);
}

pub fn initDeviceDescriptorTransfer(dev: *Device, descriptor_index: u8, lang_id: u16, data_buffer: []u8) TransferRequest {
    return initDescriptorTransfer(dev, DescriptorType.device, descriptor_index, lang_id, data_buffer);
}

pub fn initConfigurationDescriptorTransfer(dev: *Device, descriptor_index: u8, data_buffer: []u8) TransferRequest {
    return initDescriptorTransfer(dev, DescriptorType.configuration, descriptor_index, 0, data_buffer);
}

pub fn initStringDescriptorTransfer(dev: *Device, descriptor_index: u8, lang_id: u16, data_buffer: []u8) TransferRequest {
    return initDescriptorTransfer(dev, DescriptorType.string, descriptor_index, lang_id, data_buffer);
}

pub fn initInterfaceDescriptorTransfer(dev: *Device, descriptor_index: u8, data_buffer: []u8) TransferRequest {
    return initDescriptorTransfer(dev, DescriptorType.interface, descriptor_index, 0, data_buffer);
}

pub fn initEndpointDescriptorTransfer(dev: *Device, descriptor_index: u8, data_buffer: []u8) TransferRequest {
    return initDescriptorTransfer(dev, DescriptorType.endpoint, descriptor_index, 0, data_buffer);
}

pub fn initSetAddressTransfer(dev: *Device, device_address: DeviceAddress) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.host_to_device, StandardDeviceRequests.set_address, device_address, 0, 0);
    return initControlTransfer(dev, setup_packet, &.{});
}

pub fn initGetStatusTransfer(dev: *Device, data_buffer: []u8) TransferRequest {
    const length: u16 = @truncate(data_buffer.len);
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.device_to_host, StandardDeviceRequests.get_status, 0, 0, length);
    return initControlTransfer(dev, setup_packet, data_buffer);
}

pub fn initSetConfigurationTransfer(dev: *Device, config: u16) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.host_to_device, StandardDeviceRequests.set_configuration, config, 0, 0);
    return initControlTransfer(dev, setup_packet, &.{});
}

pub fn initGetConfigurationTransfer(dev: *Device, data_buffer: []u8) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.device_to_host, StandardDeviceRequests.get_configuration, 0, 0, 1);
    return initControlTransfer(dev, setup_packet, data_buffer);
}

pub fn initGetHubDescriptorTransfer(dev: *Device, descriptor_index: u8, data_buffer: []u8) TransferRequest {
    const length: u16 = @truncate(data_buffer.len);
    const val: u16 = @as(u16, DescriptorType.hub) << 8 | @as(u8, descriptor_index);
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.class, RequestTypeDirection.device_to_host, StandardDeviceRequests.get_descriptor, val, 0, length);
    return initControlTransfer(dev, setup_packet, data_buffer);
}

pub fn initGetHubStatusTransfer(dev: *Device, data_buffer: []u8) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.class, RequestTypeDirection.device_to_host, HubClassRequest.get_status, 0, 0, 4);
    return initControlTransfer(dev, setup_packet, data_buffer);
}

pub fn initHubSetHubFeatureTransfer(dev: *Device, feature: u16) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.class, RequestTypeDirection.host_to_device, HubClassRequest.set_feature, feature, 0, 0);
    return initControlTransfer(dev, setup_packet, &.{});
}

pub fn initHubClearHubFeatureTransfer(dev: *Device, feature: u16) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.class, RequestTypeDirection.host_to_device, HubClassRequest.clear_feature, feature, 0, 0);
    return initControlTransfer(dev, setup_packet, &.{});
}

pub fn initHubGetPortStatusTransfer(dev: *Device, port_number: u8, data_buffer: []u8) TransferRequest {
    const setup_packet = SetupPacket.init(RequestTypeRecipient.other, RequestTypeType.class, RequestTypeDirection.device_to_host, HubClassRequest.get_status, 0, port_number, 4);
    return initControlTransfer(dev, setup_packet, data_buffer);
}

pub fn initHubSetPortFeatureTransfer(dev: *Device, feature: u16, port_number: u8, port_indicator: u8) TransferRequest {
    const index: u16 = @as(u16, port_indicator) | port_number;
    const setup_packet = SetupPacket.init(RequestTypeRecipient.other, RequestTypeType.class, RequestTypeDirection.host_to_device, HubClassRequest.set_feature, feature, index, 0);
    return initControlTransfer(dev, setup_packet, &.{});
}

pub fn initHubClearPortFeatureTransfer(dev: *Device, feature: u16, port_number: u8) TransferRequest {
    const index: u16 = @as(u16, port_number);
    const setup_packet = SetupPacket.init(RequestTypeRecipient.other, RequestTypeType.class, RequestTypeDirection.host_to_device, HubClassRequest.clear_feature, feature, index, 0);
    return initControlTransfer(dev, setup_packet, &.{});
}
