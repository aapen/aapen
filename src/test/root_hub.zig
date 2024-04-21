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
const HubFeature = usb.HubFeature;
const InterfaceClass = usb.InterfaceClass;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const LangID = usb.LangID;
const PortStatus = usb.PortStatus;
const PortFeature = usb.PortFeature;
const StringDescriptor = usb.StringDescriptor;
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferCompletionStatus = usb.TransferCompletionStatus;
const TransferFactory = usb.TransferFactory;
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
    expectEqual(expected_status, xfer.status);
}

fn supportedTransferTypes() !void {
    var endpoint_iso: EndpointDescriptor = .{
        .header = undefined,
        .endpoint_address = 0,
        .attributes = .{
            .endpoint_type = TransferType.isochronous,
            .iso_synch_type = 0,
            .usage_type = 0,
        },
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
        .header = undefined,
        .endpoint_address = 0,
        .attributes = .{
            .endpoint_type = TransferType.bulk,
            .iso_synch_type = 0,
            .usage_type = 0,
        },
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

fn getDeviceDescriptor() !void {
    const buffer_size = @sizeOf(DeviceDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initDescriptorTransfer(&nulldev, DescriptorType.device, 0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    const device_descriptor = std.mem.bytesAsValue(DeviceDescriptor, xfer.data[0..@sizeOf(DeviceDescriptor)]);

    expectEqual(DescriptorType.device, device_descriptor.header.descriptor_type);
    expectEqual(DeviceClass.hub, device_descriptor.device_class);
    expectEqual(@as(u8, 0), device_descriptor.device_subclass);
    expectEqual(@as(u8, 1), device_descriptor.device_protocol);
    expect(@src(), device_descriptor.configuration_count >= 1);
    expect(@src(), device_descriptor.max_packet_size >= 8);
}

fn getDeviceDescriptorShortBuffer() !void {
    const short_buffer_len: u16 = @as(u16, @sizeOf(DeviceDescriptor)) / 2;
    var buffer: [short_buffer_len]u8 = undefined;

    var xfer = TransferFactory.initDescriptorTransfer(&nulldev, DescriptorType.device, 0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(u19, short_buffer_len), xfer.actual_size);
}

fn getConfigurationDescriptor() !void {
    const buffer_size = ConfigurationDescriptor.STANDARD_LENGTH + InterfaceDescriptor.STANDARD_LENGTH + EndpointDescriptor.STANDARD_LENGTH;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initConfigurationDescriptorTransfer(&nulldev, 1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    var config = try DeviceConfiguration.initFromBytes(helpers.allocator, &buffer);
    defer {
        config.deinit();
        helpers.allocator.destroy(config);
    }

    expectEqual(DescriptorType.configuration, config.configuration_descriptor.header.descriptor_type);
    expect(@src(), config.configuration_descriptor.interface_count >= 1);

    expectEqual(DescriptorType.interface, config.interfaces[0].?.header.descriptor_type);
    expectEqual(InterfaceClass.hub, config.interfaces[0].?.interface_class);
    expect(@src(), config.interfaces[0].?.endpoint_count >= 1);

    expectEqual(DescriptorType.endpoint, config.endpoints[0][0].?.header.descriptor_type);
    expect(@src(), config.endpoints[0][0].?.max_packet_size >= 4);
}

fn getConfigurationDescriptorShortBuffer() !void {
    const buffer_size = (@sizeOf(ConfigurationDescriptor) + @sizeOf(InterfaceDescriptor) + @sizeOf(EndpointDescriptor)) / 2;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initConfigurationDescriptorTransfer(&nulldev, 1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getStringDescriptors() !void {
    // Should be a descriptor header plus a single u16
    const buffer_size = @sizeOf(usb.StringDescriptor);
    var buffer: [buffer_size]u8 align(2) = undefined;

    var xfer = TransferFactory.initStringDescriptorTransfer(&nulldev, 0, LangID.none, &buffer);
    expectTransferCompletionStatus(.ok, &xfer);

    const string = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data[0..buffer_size])));

    expectEqualSlices(u16, &.{0x0409}, string.body[0..1]);

    // check string at index 2
    xfer = TransferFactory.initStringDescriptorTransfer(&nulldev, 2, LangID.none, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    const string2 = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data[0..buffer_size])));
    const str_slice = try string2.asSlice(helpers.allocator);
    defer helpers.allocator.free(str_slice);

    expectEqualSlices(u8, "USB", str_slice[0..3]);
}

fn getStringDescriptorShortBuffer() !void {
    const buffer_size = @sizeOf(usb.Header) + 4;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initStringDescriptorTransfer(&nulldev, 1, LangID.none, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getStatus() !void {
    const buffer_size = @sizeOf(u16);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetStatusTransfer(&nulldev, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setConfiguration() !void {
    var xfer = TransferFactory.initSetConfigurationTransfer(&nulldev, 1);
    expectTransferCompletionStatus(.ok, &xfer);

    var xfer2 = TransferFactory.initSetConfigurationTransfer(&nulldev, 99);
    expectTransferCompletionStatus(.unsupported_request, &xfer2);
}

fn getConfiguration() !void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetConfigurationTransfer(&nulldev, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(u8, buffer_size), xfer.data[0]);
}

fn getDescriptor() !void {
    const buffer_size = @sizeOf(HubDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetHubDescriptorTransfer(&nulldev, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    const hub_descriptor = std.mem.bytesAsValue(HubDescriptor, xfer.data[0..@sizeOf(HubDescriptor)]);

    expectEqual(DescriptorType.hub, hub_descriptor.header.descriptor_type);
    expectEqual(@as(u8, 1), hub_descriptor.number_ports);
}

fn getHubStatus() !void {
    const buffer_size = 4;
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initGetHubStatusTransfer(&nulldev, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getPortStatus() !void {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initHubGetPortStatusTransfer(&nulldev, 1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn getPortPowerStatus() !bool {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;

    var xfer = TransferFactory.initHubGetPortStatusTransfer(&nulldev, 1, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);

    const port_status = std.mem.bytesAsValue(PortStatus, xfer.data[0..@sizeOf(PortStatus)]);

    return port_status.port_status.power == 1;
}

fn setPortFeature() !void {
    const buffer_size = 0;

    var xfer = TransferFactory.initHubSetPortFeatureTransfer(&nulldev, PortFeature.port_power, 1, 0);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setPortFeatureReset() !void {
    const buffer_size = 0;

    var xfer = TransferFactory.initHubSetPortFeatureTransfer(&nulldev, PortFeature.port_reset, 1, 0);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setAddress() !void {
    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer = TransferFactory.initDescriptorTransfer(&nulldev, DescriptorType.device, 0, 0, &buffer);

    expectTransferCompletionStatus(.ok, &xfer);

    expectEqual(@as(TransferBytes, buffer_size), xfer.actual_size);
}

fn setHubFeature() !void {
    var xfer = TransferFactory.initHubSetHubFeatureTransfer(&nulldev, HubFeature.c_hub_local_power);
    expectTransferCompletionStatus(.unsupported_request, &xfer);
}

fn clearHubFeature() !void {
    var xfer = TransferFactory.initHubClearHubFeatureTransfer(&nulldev, HubFeature.c_hub_local_power);
    expectTransferCompletionStatus(.unsupported_request, &xfer);
}

fn hubHoldInterruptRequestUntilChange() !void {
    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    var xfer = TransferFactory.initInterruptTransfer(&nulldev, &buffer);
    expectTransferCompletionStatus(.incomplete, &xfer);
}
