const std = @import("std");
const log = std.log.scoped(.usb);

const usb = @import("../../usb.zig");
const ClassRequestCode = usb.ClassRequestCode;
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DescriptorType = usb.DescriptorType;
const DeviceClass = usb.DeviceClass;
const DeviceDescriptor = usb.DeviceDescriptor;
const DeviceStatus = usb.DeviceStatus;
const EndpointDescriptor = usb.EndpointDescriptor;
const Error = usb.Error;
const HubClassRequest = usb.hub.ClassRequest;
const HubDescriptor = usb.HubDescriptor;
const InterfaceClass = usb.InterfaceClass;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const PortFeature = usb.PortFeature;
const PortStatus = usb.PortStatus;
const RequestTypeRecipient = usb.RequestTypeRecipient;
const RequestTypeType = usb.RequestTypeType;
const StandardDeviceRequests = usb.StandardDeviceRequests;
const StringDescriptor = usb.StringDescriptor;
const Transfer = usb.Transfer;

// ----------------------------------------------------------------------
// Mutable state
// ----------------------------------------------------------------------
var root_hub_status: DeviceStatus = .{
    .status = usb.STATUS_SELF_POWERED,
};

var host_port_status: PortStatus = .{
    .port_status = @bitCast(@as(u16, 0)),
    .port_change = @bitCast(@as(u16, 0)),
};

// ----------------------------------------------------------------------
// Static data
// ----------------------------------------------------------------------
const root_hub_device_descriptor: DeviceDescriptor = .{
    .header = .{
        .length = @sizeOf(DeviceDescriptor),
        .descriptor_type = .device,
    },
    .usb_standard_compliance = 0x200,
    .device_class = @intFromEnum(DeviceClass.hub),
    .device_subclass = 0,
    .device_protocol = 0,
    .max_packet_size = 64,
    .vendor = 0,
    .product = 0,
    .device_release = 0,
    .manufacturer_name = 0,
    .product_name = 0,
    .serial_number = 0,
    .configuration_count = 1,
};

const RootHubConfiguration = extern struct {
    configuration: ConfigurationDescriptor,
    interface: InterfaceDescriptor,
    endpoint: EndpointDescriptor,
};

const root_hub_configuration: RootHubConfiguration = .{
    .configuration = .{
        .header = .{
            .length = @sizeOf(ConfigurationDescriptor),
            .descriptor_type = .configuration,
        },
        .total_length = @sizeOf(RootHubConfiguration),
        .interface_count = 1,
        .configuration_value = 1,
        .configuration = 0,
        .attributes = .{
            .remote_wakeup = 0,
            .self_powered = 0,
        },
        .power_max = 0,
    },
    .interface = .{
        .header = .{
            .length = @sizeOf(InterfaceDescriptor),
            .descriptor_type = .interface,
        },
        .interface_number = 0,
        .alternate_setting = 0,
        .endpoint_count = 1,
        .interface_class = InterfaceClass.hub,
        .interface_subclass = 0,
        .interface_protocol = 0,
        .interface_string = 0,
    },
    .endpoint = .{
        .header = .{
            .length = @sizeOf(EndpointDescriptor),
            .descriptor_type = .endpoint,
        },
        .endpoint_address = (1 << 7) | 1,
        .attributes = @bitCast(@as(u8, 0x03)),
        .max_packet_size = 64,
        .interval = 0xff,
    },
};

fn mkStringDescriptor(comptime payload: []const u16) StringDescriptor {
    if (payload.len > 31) @compileError("This unit only supports string descriptors up to 31 U16's long");

    var body: [31]u16 = [_]u16{0} ** 31;
    @memcpy(body[0..payload.len], payload);

    return .{
        .header = .{
            .length = @sizeOf(usb.Header) + 2 * payload.len,
            .descriptor_type = .string,
        },
        .body = body,
    };
}

const root_hub_string_0 = mkStringDescriptor(&[_]u16{0x0409});
const root_hub_string_1 = mkStringDescriptor(&[_]u16{ 'U', 'S', 'B', ' ', '2', '.', '0', ' ', 'R', 'o', 'o', 't', ' ', 'H', 'u', 'b' });

// const root_hub_string_1: StringDescriptor = .{
//     .header = .{
//         .length = @sizeOf(StringDescriptor) + 32,
//         .descriptor_type = .string,
//     },
//     .body = root_hub_string_1_payload,
// };

const root_hub_strings = &[_]StringDescriptor{
    root_hub_string_0,
    root_hub_string_1,
};

const RootHubDescriptor = packed struct {
    base: HubDescriptor,
    extra_data: [2]u8,
};

const root_hub_hub_descriptor: RootHubDescriptor = .{
    .base = .{
        .header = .{
            .length = @sizeOf(HubDescriptor) + 2,
            .descriptor_type = .hub,
        },
        .number_ports = 1,
        .characteristics = @bitCast(0),
        .power_on_to_power_good = 0,
        .controller_current = 0,
    },
    .extra_data = .{ 0x00, 0xff },
};

// ----------------------------------------------------------------------
// Behavior
// ----------------------------------------------------------------------
const Handler = struct { RequestTypeType, ?u8, ?usb.RequestTypeRecipient, *const fn (transfer: *Transfer) usb.Error!void };

// null means "don't care", ignore this field when dispatching.

const handlers: []const Handler = &.{
    .{ .standard, @intFromEnum(StandardDeviceRequests.get_status), null, hubGetDeviceStatus },
    .{ .standard, @intFromEnum(StandardDeviceRequests.set_address), null, hubSetAddress },
    .{ .standard, @intFromEnum(StandardDeviceRequests.get_descriptor), null, hubGetDescriptor },
    .{ .standard, @intFromEnum(StandardDeviceRequests.get_configuration), null, hubGetConfiguration },
    .{ .standard, @intFromEnum(StandardDeviceRequests.set_configuration), null, hubSetConfiguration },
    .{ .class, @intFromEnum(ClassRequestCode.get_descriptor), null, hubGetHubDescriptor },
    .{ .class, @intFromEnum(ClassRequestCode.get_status), .device, hubGetHubStatus },
    .{ .class, @intFromEnum(ClassRequestCode.get_status), .other, hubGetPortStatus },
    .{ .class, @intFromEnum(ClassRequestCode.set_feature), .device, hubSetHubFeature },
    .{ .class, @intFromEnum(ClassRequestCode.set_feature), .other, hubSetPortFeature },
    .{ .class, @intFromEnum(ClassRequestCode.clear_feature), .device, hubClearHubFeature },
    .{ .class, @intFromEnum(ClassRequestCode.clear_feature), .other, hubClearPortFeature },
};

fn hubGetDeviceDescriptor(transfer: *Transfer) usb.Error!void {
    @memcpy(transfer.data_buffer, std.mem.asBytes(&root_hub_device_descriptor));
    return;
}

fn hubGetConfigurationDescriptor(transfer: *Transfer) usb.Error!void {
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index == 1) {
        @memcpy(transfer.data_buffer, std.mem.asBytes(&root_hub_configuration));
    } else {
        return Error.UnsupportedRequest;
    }
}

fn hubGetStringDescriptor(transfer: *Transfer) usb.Error!void {
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index > root_hub_strings.len) {
        return Error.UnsupportedRequest;
    }

    const string = &root_hub_strings[descriptor_index];
    const requested_length = transfer.setup.data_size;
    const provided_length = @min(requested_length, string.header.length);
    @memcpy(transfer.data_buffer[0..provided_length], std.mem.asBytes(string)[0..provided_length]);
}

fn hubGetDeviceStatus(transfer: *Transfer) usb.Error!void {
    _ = transfer;
}

fn hubSetAddress(_: *Transfer) usb.Error!void {
    return;
}

fn hubGetDescriptor(transfer: *Transfer) usb.Error!void {
    return switch (transfer.setup.value >> 8) {
        @intFromEnum(DescriptorType.device) => hubGetDeviceDescriptor(transfer),
        @intFromEnum(DescriptorType.configuration) => hubGetConfigurationDescriptor(transfer),
        @intFromEnum(DescriptorType.string) => hubGetStringDescriptor(transfer),
        else => Error.UnsupportedRequest,
    };
}

fn hubGetConfiguration(transfer: *Transfer) usb.Error!void {
    transfer.data_buffer[0] = 1;
}

fn hubSetConfiguration(transfer: *Transfer) usb.Error!void {
    if (transfer.setup.value != 1) {
        return Error.UnsupportedRequest;
    }
}

fn hubGetHubDescriptor(transfer: *Transfer) usb.Error!void {
    _ = transfer;
}

fn hubGetHubStatus(transfer: *Transfer) usb.Error!void {
    _ = transfer;
}

fn hubGetPortStatus(transfer: *Transfer) usb.Error!void {
    _ = transfer;
}

fn hubSetHubFeature(_: *Transfer) usb.Error!void {
    return usb.Error.UnsupportedRequest;
}

fn hubSetPortFeature(transfer: *Transfer) usb.Error!void {
    const feature = transfer.setup.value;

    switch (feature) {
        @intFromEnum(PortFeature.port_power) => return hostPortPowerOn(),
        @intFromEnum(PortFeature.port_reset) => return hostPortReset(),
        else => return usb.Error.UnsupportedRequest,
    }
}

fn hubClearHubFeature(_: *Transfer) usb.Error!void {
    return usb.Error.UnsupportedRequest;
}

fn hubClearPortFeature(transfer: *Transfer) usb.Error!void {
    const feature = transfer.setup.value;

    switch (feature) {
        @intFromEnum(PortFeature.c_port_connection) => host_port_status.port_change.connected_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_enable) => host_port_status.port_change.enabled_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_suspend) => host_port_status.port_change.suspended_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_over_current) => host_port_status.port_change.overcurrent_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_reset) => host_port_status.port_change.reset_changed = .not_changed,
        else => return usb.Error.UnsupportedRequest,
    }
    return;
}

fn hostPortPowerOn() usb.Error!void {}

fn hostPortReset() usb.Error!void {}

pub fn hubHandleTransfer(transfer: *Transfer) !void {
    if (transfer.transfer_type != .control) {
        return Error.UnsupportedRequest;
    }

    const req_type = transfer.setup.request_type.type;
    const request = transfer.setup.request;
    const recipient = transfer.setup.request_type.recipient;

    for (handlers) |h| {
        if (req_type == h[0] and (h[1] == null or h[1] == request) and (h[2] == null or h[2] == recipient)) {
            return h[3](transfer);
        }
    }
    return Error.UnsupportedRequest;
}

// ----------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectError = std.testing.expectError;

test "only control transfers are supported" {
    var iso: Transfer = .{
        .transfer_type = .isochronous,
        .setup = undefined,
        .data_buffer = &.{},
    };

    var bulk: Transfer = .{
        .transfer_type = .bulk,
        .setup = undefined,
        .data_buffer = &.{},
    };
    var interrupt: Transfer = .{
        .transfer_type = .interrupt,
        .setup = undefined,
        .data_buffer = &.{},
    };

    try expectError(Error.UnsupportedRequest, hubHandleTransfer(&iso));
    try expectError(Error.UnsupportedRequest, hubHandleTransfer(&bulk));
    try expectError(Error.UnsupportedRequest, hubHandleTransfer(&interrupt));
}

test "get device descriptor" {
    var buffer: [@sizeOf(DeviceDescriptor)]u8 = undefined;

    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.device, 0, 0, @sizeOf(DeviceDescriptor)),
        .data_buffer = &buffer,
    };

    try hubHandleTransfer(&xfer);

    const returned_len: u8 = xfer.data_buffer[0];
    _ = returned_len;
    const device_descriptor = std.mem.bytesAsValue(DeviceDescriptor, xfer.data_buffer[0..@sizeOf(DeviceDescriptor)]);

    try expectEqual(DescriptorType.device, device_descriptor.header.descriptor_type);
    try expectEqual(@as(u8, @intFromEnum(DeviceClass.hub)), device_descriptor.device_class);
    try expectEqual(@as(u8, 0), device_descriptor.device_subclass);
    try expectEqual(@as(u8, 0), device_descriptor.device_protocol);
    try expect(device_descriptor.configuration_count >= 1);
    try expect(device_descriptor.max_packet_size >= 8);
}

test "get configuration descriptor" {
    const buffer_size = @sizeOf(ConfigurationDescriptor) + @sizeOf(InterfaceDescriptor) + @sizeOf(EndpointDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.configuration, 1, 0, buffer_size),
        .data_buffer = &buffer,
    };

    try hubHandleTransfer(&xfer);

    const config_start = 0;
    const config_end = @sizeOf(ConfigurationDescriptor);
    const iface_start = config_end;
    const iface_end = iface_start + @sizeOf(InterfaceDescriptor);
    const endpoint_start = iface_end;
    const endpoint_end = endpoint_start + @sizeOf(EndpointDescriptor);

    const configuration_descriptor = std.mem.bytesAsValue(ConfigurationDescriptor, xfer.data_buffer[config_start..config_end]);
    try expectEqual(@as(u8, @sizeOf(ConfigurationDescriptor)), configuration_descriptor.header.length);
    try expectEqual(DescriptorType.configuration, configuration_descriptor.header.descriptor_type);
    try expect(configuration_descriptor.interface_count >= 1);

    const interface_descriptor = std.mem.bytesAsValue(InterfaceDescriptor, xfer.data_buffer[iface_start..iface_end]);
    try expectEqual(@as(u8, @sizeOf(InterfaceDescriptor)), interface_descriptor.header.length);
    try expectEqual(DescriptorType.interface, interface_descriptor.header.descriptor_type);
    try expect(interface_descriptor.endpoint_count >= 1);
    try expectEqual(InterfaceClass.hub, interface_descriptor.interface_class);

    const endpoint_descriptor = std.mem.bytesAsValue(EndpointDescriptor, xfer.data_buffer[endpoint_start..endpoint_end]);
    try expectEqual(@as(u8, @sizeOf(EndpointDescriptor)), endpoint_descriptor.header.length);
    try expectEqual(DescriptorType.endpoint, endpoint_descriptor.header.descriptor_type);
    try expect(endpoint_descriptor.max_packet_size >= 8);
}

test "get string descriptors" {
    // Should be a descriptor header plus a single u16
    const buffer_size = @sizeOf(usb.StringDescriptor);
    var buffer: [buffer_size]u8 align(2) = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.string, 0, 0, buffer_size),
        .data_buffer = &buffer,
    };

    try hubHandleTransfer(&xfer);

    const string = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data_buffer[0..buffer_size])));

    try expectEqualSlices(u16, &.{0x0409}, string.body[0..1]);

    // check string at index 1
    xfer.setup = usb.setupDescriptorQuery(.string, 1, 0, buffer_size);

    try hubHandleTransfer(&xfer);

    const string2 = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data_buffer[0..buffer_size])));
    const str_slice = try string2.asSlice(std.testing.allocator);
    defer std.testing.allocator.free(str_slice);

    try expectEqualSlices(u8, "USB", str_slice[0..3]);
    std.debug.print("\nstring returned was {any}\n", .{string2.body});
}

test "we support 'set configuration' iff the chosen configuration is 1" {
    var buffer: [0]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetConfiguration(1),
        .data_buffer = &buffer,
    };

    try hubHandleTransfer(&xfer);

    xfer.setup = usb.setupSetConfiguration(99);

    try expectError(Error.UnsupportedRequest, hubHandleTransfer(&xfer));
}

test "'get configuration' always returns 1" {
    var buffer: [1]u8 = undefined;
    var getconfig: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetConfiguration(),
        .data_buffer = &buffer,
    };

    try hubHandleTransfer(&getconfig);

    try expectEqual(@as(u8, 1), getconfig.data_buffer[0]);
}

test "we silently support 'set address'" {
    var buffer: [0]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetAddress(123),
        .data_buffer = &buffer,
    };

    try hubHandleTransfer(&xfer);
}

test "we don't support 'set hub feature'" {
    var buffer: [0]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetHubFeature(.c_hub_local_power),
        .data_buffer = &buffer,
    };

    try expectError(Error.UnsupportedRequest, hubHandleTransfer(&xfer));
}

test "we don't support 'clear hub feature'" {
    var buffer: [0]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupClearHubFeature(.c_hub_local_power),
        .data_buffer = &buffer,
    };

    try expectError(Error.UnsupportedRequest, hubHandleTransfer(&xfer));
}
