const std = @import("std");
const root = @import("root");

const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectEqualSlices = helpers.expectEqualSlices;
const expectError = helpers.expectError;

const usb = @import("../usb.zig");
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DescriptorType = usb.DescriptorType;
const DeviceClass = usb.DeviceClass;
const DeviceConfiguration = usb.DeviceConfiguration;
const DeviceDescriptor = usb.DeviceDescriptor;
const EndpointDescriptor = usb.EndpointDescriptor;
const HubDescriptor = usb.HubDescriptor;
const InterfaceClass = usb.InterfaceClass;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const LangID = usb.LangID;
const PortStatus = usb.PortStatus;
const StringDescriptor = usb.StringDescriptor;
const Transfer = usb.Transfer;
const TransferBytes = usb.TransferBytes;
const TransferFactory = usb.TransferFactory;
const TransferCompletionStatus = usb.TransferCompletionStatus;

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

fn expectTransferCompletionStatus(expected_status: TransferCompletionStatus, xfer: *Transfer) void {
    var regs: HostRegisters = fakeRegisters();
    var hub: RootHub = .{};
    hub.init(&regs);

    hub.hubHandleTransfer(xfer);
    expectEqual(expected_status, xfer.status);
}

fn supportedTransferTypes() !void {
    var iso: Transfer = .{
        .endpoint_type = .isochronous,
        .setup = undefined,
        .data_buffer = &.{},
    };

    var bulk: Transfer = .{
        .endpoint_type = .bulk,
        .setup = undefined,
        .data_buffer = &.{},
    };

    expectTransferCompletionStatus(.unsupported_request, &iso);
    expectTransferCompletionStatus(.unsupported_request, &bulk);
}

fn getDeviceDescriptor() !void {
    const buffer_size = @sizeOf(DeviceDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initDescriptorTransfer(.device, 0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    const device_descriptor = std.mem.bytesAsValue(DeviceDescriptor, xfer.data_buffer[0..@sizeOf(DeviceDescriptor)]);

    expectEqual(DescriptorType.device, device_descriptor.header.descriptor_type);
    expectEqual(@as(u8, @intFromEnum(DeviceClass.hub)), device_descriptor.device_class);
    expectEqual(@as(u8, 0), device_descriptor.device_subclass);
    expectEqual(@as(u8, 0), device_descriptor.device_protocol);
    expect(device_descriptor.configuration_count >= 1);
    expect(device_descriptor.max_packet_size >= 8);
}

fn getDeviceDescriptorShortBuffer() !void {
    const short_buffer_len: u16 = @as(u16, @sizeOf(DeviceDescriptor)) / 2;
    var buffer: [short_buffer_len]u8 = undefined;

    var xfer = TransferFactory.initDescriptorTransfer(.device, 0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(u19, short_buffer_len), xfer.actual_size);
}

fn getConfigurationDescriptor() !void {
    const buffer_size = ConfigurationDescriptor.STANDARD_LENGTH + InterfaceDescriptor.STANDARD_LENGTH + EndpointDescriptor.STANDARD_LENGTH;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initConfigurationDescriptorTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    var config = try DeviceConfiguration.initFromBytes(helpers.allocator, &buffer);
    defer {
        config.deinit();
        helpers.allocator.destroy(config);
    }

    expectEqual(DescriptorType.configuration, config.configuration_descriptor.header.descriptor_type);
    expect(config.configuration_descriptor.interface_count >= 1);

    expectEqual(DescriptorType.interface, config.interfaces[0].?.header.descriptor_type);
    expectEqual(InterfaceClass.hub, config.interfaces[0].?.interface_class);
    expect(config.interfaces[0].?.endpoint_count >= 1);

    expectEqual(DescriptorType.endpoint, config.endpoints[0][0].?.header.descriptor_type);
    expect(config.endpoints[0][0].?.max_packet_size >= 8);
}

fn getConfigurationDescriptorShortBuffer() !void {
    const buffer_size = (@sizeOf(ConfigurationDescriptor) + @sizeOf(InterfaceDescriptor) + @sizeOf(EndpointDescriptor)) / 2;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initConfigurationDescriptorTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getStringDescriptors() !void {
    // Should be a descriptor header plus a single u16
    const buffer_size = @sizeOf(usb.StringDescriptor);
    var buffer: [buffer_size]u8 align(2) = undefined;

    var xfer = TransferFactory.initStringDescriptorTransfer(0, LangID.none, &buffer);
    expectTransferCompletionStatus(.ok, &xfer);

    const string = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data_buffer[0..buffer_size])));

    expectEqualSlices(u16, &.{0x0409}, string.body[0..1]);

    // check string at index 1
    xfer = TransferFactory.initStringDescriptorTransfer(1, LangID.none, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    const string2 = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data_buffer[0..buffer_size])));
    const str_slice = try string2.asSlice(helpers.allocator);
    defer helpers.allocator.free(str_slice);

    expectEqualSlices(u8, "USB", str_slice[0..3]);
}

fn getStringDescriptorShortBuffer() !void {
    const buffer_size = @sizeOf(usb.Header) + 4;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initStringDescriptorTransfer(1, LangID.none, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getStatus() !void {
    const buffer_size = @sizeOf(u16);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetStatusTransfer(&buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setConfiguration() !void {
    var xfer = TransferFactory.initSetConfigurationTransfer(1);
    expectTransferCompletionStatus(.ok, &xfer);

    var xfer2 = TransferFactory.initSetConfigurationTransfer(99);
    expectTransferCompletionStatus(.unsupported_request, &xfer2);
}

fn getConfiguration() !void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetConfigurationTransfer(&buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(u8, buffer_size), xfer.data_buffer[0]);
}

fn getDescriptor() !void {
    const buffer_size = @sizeOf(HubDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetHubDescriptorTransfer(0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    const hub_descriptor = std.mem.bytesAsValue(HubDescriptor, xfer.data_buffer[0..@sizeOf(HubDescriptor)]);

    expectEqual(DescriptorType.hub, hub_descriptor.header.descriptor_type);
    expectEqual(@as(u8, 1), hub_descriptor.number_ports);
}

fn getHubStatus() !void {
    const buffer_size = 4;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetHubStatusTransfer(&buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getPortStatus() !void {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initHubGetPortStatusTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getPortPowerStatus() !bool {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initHubGetPortStatusTransfer(1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    const port_status = std.mem.bytesAsValue(PortStatus, xfer.data_buffer[0..@sizeOf(PortStatus)]);

    return port_status.port_status.power == 1;
}

fn setPortFeature() !void {
    const buffer_size = 0;

    var xfer = TransferFactory.initHubSetPortFeatureTransfer(.port_power, 1, 0);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setPortFeatureReset() !void {
    const buffer_size = 0;

    var xfer = TransferFactory.initHubSetPortFeatureTransfer(.port_reset, 1, 0);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setAddress() !void {
    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer = TransferFactory.initDescriptorTransfer(.device, 0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setHubFeature() !void {
    var xfer = TransferFactory.initHubSetHubFeatureTransfer(.c_hub_local_power);
    expectTransferCompletionStatus(.unsupported_request, &xfer);
}

fn clearHubFeature() !void {
    var xfer = TransferFactory.initHubClearHubFeatureTransfer(.c_hub_local_power);
    expectTransferCompletionStatus(.unsupported_request, &xfer);
}

fn hubHoldInterruptRequestUntilChange() !void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    var xfer = TransferFactory.initInterruptTransfer(&buffer);
    expectTransferCompletionStatus(.incomplete, &xfer);
}
