const std = @import("std");
const log = std.log.scoped(.usb);
const builtin = @import("builtin");

const time = @import("../../time.zig");
const delayMillis = time.delayMillis;

const usb = @import("../../usb.zig");
const ClassRequestCode = usb.ClassRequestCode;
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DescriptorType = usb.DescriptorType;
const DeviceClass = usb.DeviceClass;
const DeviceDescriptor = usb.DeviceDescriptor;
const DeviceStatus = usb.DeviceStatus;
const EndpointDescriptor = usb.EndpointDescriptor;
const HubClassRequest = usb.hub.ClassRequest;
const HubDescriptor = usb.HubDescriptor;
const HubStatus = usb.HubStatus;
const InterfaceClass = usb.InterfaceClass;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const PortFeature = usb.PortFeature;
const PortStatus = usb.PortStatus;
const RequestTypeRecipient = usb.RequestTypeRecipient;
const RequestTypeType = usb.RequestTypeType;
const StandardDeviceRequests = usb.StandardDeviceRequests;
const StringDescriptor = usb.StringDescriptor;
const Transfer = usb.Transfer;
const TransferStatus = usb.TransferStatus;

const registers = @import("registers.zig");
const HostPortStatusAndControl = registers.HostPortStatusAndControl;

// ----------------------------------------------------------------------
// Mutable state
// ----------------------------------------------------------------------
var host_registers: ?*volatile registers.HostRegisters = null;

var root_hub_device_status: DeviceStatus = usb.STATUS_SELF_POWERED;

var root_hub_hub_status: HubStatus = .{
    .hub_status = .{
        .local_power_source = .local_power_good,
        .overcurrent = .not_detected,
    },
    .change_status = .{
        .local_power_changed = .not_changed,
        .overcurrent_changed = .not_changed,
    },
};

var root_hub_port_status: PortStatus = .{
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

const root_hub_strings = &[_]StringDescriptor{
    root_hub_string_0,
    root_hub_string_1,
};

const RootHubDescriptor = extern struct {
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
        .characteristics = @bitCast(@as(u16, 0)),
        .power_on_to_power_good = 0,
        .controller_current = 0,
    },
    .extra_data = .{ 0x00, 0xff },
};

// ----------------------------------------------------------------------
// Hardware interaction
// ----------------------------------------------------------------------

fn hostPortSafeRead(host_reg: *volatile registers.HostRegisters) HostPortStatusAndControl {
    var hw_status = host_reg.port;

    // We zero out some bits because they are "write clear" and we
    // could accidentally reset them if they read as 1
    hw_status.enabled = 0;
    hw_status.connect_changed = 0;
    hw_status.enabled_changed = 0;
    hw_status.overcurrent_changed = 0;

    return hw_status;
}

fn hostPortPowerOn() TransferStatus {
    if (host_registers) |host_reg| {
        var hw_status = hostPortSafeRead(host_reg);

        hw_status.power = 1;

        host_reg.port = hw_status;
    }
    return .ok;
}

fn hostPortPowerOff() TransferStatus {
    if (host_registers) |host_reg| {
        var hw_status = hostPortSafeRead(host_reg);

        hw_status.power = 0;

        host_reg.port = hw_status;
    }
    return .ok;
}

fn hostPortReset() TransferStatus {
    if (host_registers) |host_reg| {
        var hw_status = hostPortSafeRead(host_reg);
        hw_status.reset = 1;
        host_reg.port = hw_status;

        delayMillis(60);

        hw_status.reset = 0;
        host_reg.port = hw_status;
    }
    return .ok;
}

// ----------------------------------------------------------------------
// Interrupt Handler
// ----------------------------------------------------------------------

// This is called from the DWC core driver when it receives a 'port'
// interrupt
pub fn hubHandlePortInterrupt() void {
    if (host_registers) |host_reg| {
        const hw_status = host_reg.port;

        root_hub_port_status.port_status.connected = hw_status.connect;
        root_hub_port_status.port_status.enabled = hw_status.enabled;
        root_hub_port_status.port_status.suspended = hw_status.suspended;
        root_hub_port_status.port_status.overcurrent = hw_status.overcurrent;
        root_hub_port_status.port_status.reset = hw_status.reset;
        root_hub_port_status.port_status.powered = hw_status.power;
        root_hub_port_status.port_status.low_speed_device = hw_status.speed == .low;
        root_hub_port_status.port_status.high_speed_device = hw_status.speed == .high;

        root_hub_port_status.port_change.connected_changed = hw_status.connect_changed;
        root_hub_port_status.port_change.enabled_changed = hw_status.enabled_changed;
        root_hub_port_status.port_change.overcurrent_changed = hw_status.overcurrent_changed;

        // Clear the interrupts, which are WC ("write clear") bits by
        // writing the register value back to itself, except for the
        // enabled bit!
        hw_status.enabled = 0;
        host_reg.port = hw_status;

        hubNotifyPortChange();
    }
}

// ----------------------------------------------------------------------
// Interrupt Transfer Handling
// ----------------------------------------------------------------------

// An "interrupt" transfer is a request to be interrupted when an
// event occurs. The hub receives an interrupt transfer and sits on it
// until something "interesting" occurs. At that point the hub
// completes the transfer, thereby interrupting the host software with
// the information. This is not the same as a hardware interrupt
// within the host machine. (Though a hardware interrupt may result
// from completing the USB interrupt transfer!)

var pending_interrupt_transfer: ?*Transfer = null;

fn hubNotifyPortChange() void {
    if (pending_interrupt_transfer) |request| {
        pending_interrupt_transfer = null;
        if (request.data_buffer.len >= 1) {
            request.data_buffer[0] = 0x02;
            request.actual_size = 1;
        } else {
            request.actual_size = 0;
        }
        pending_interrupt_transfer.complete(.ok);
    }
}

// ----------------------------------------------------------------------
// Request Handling Behavior
// ----------------------------------------------------------------------
const Handler = struct { RequestTypeType, ?u8, ?usb.RequestTypeRecipient, *const fn (transfer: *Transfer) TransferStatus };

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

fn replyWithStructure(transfer: *Transfer, v: *const anyopaque, size: usize) TransferStatus {
    const requested_length = transfer.setup.data_size;
    const provided_length = @min(requested_length, size);
    @memcpy(transfer.data_buffer[0..provided_length], @as([*]const u8, @ptrCast(v))[0..provided_length]);
    transfer.actual_size = provided_length;
    return .ok;
}

fn hubGetDeviceDescriptor(transfer: *Transfer) TransferStatus {
    return replyWithStructure(transfer, &root_hub_device_descriptor, @sizeOf(@TypeOf(root_hub_device_descriptor)));
}

fn hubGetConfigurationDescriptor(transfer: *Transfer) TransferStatus {
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index == 1) {
        return replyWithStructure(transfer, &root_hub_configuration, @sizeOf(@TypeOf(root_hub_configuration)));
    } else {
        log.warn("hubGetConfigurationDescriptor: descriptor_index {d} not supported", .{descriptor_index});
        return .unsupported_request;
    }
}

fn hubGetStringDescriptor(transfer: *Transfer) TransferStatus {
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index > root_hub_strings.len) {
        log.warn("hubGetStringDescriptor: descriptor_index {d} is greater than {d}", .{ descriptor_index, root_hub_strings.len });
        return .unsupported_request;
    }

    const string = &root_hub_strings[descriptor_index];
    return replyWithStructure(transfer, string, string.header.length);
}

fn hubGetDeviceStatus(transfer: *Transfer) TransferStatus {
    return replyWithStructure(transfer, &root_hub_device_status, @sizeOf(@TypeOf(root_hub_device_status)));
}

fn hubSetAddress(_: *Transfer) TransferStatus {
    return .ok;
}

fn hubGetDescriptor(transfer: *Transfer) TransferStatus {
    const descriptor_type = transfer.setup.value >> 8;
    switch (descriptor_type) {
        @intFromEnum(DescriptorType.device) => return hubGetDeviceDescriptor(transfer),
        @intFromEnum(DescriptorType.configuration) => return hubGetConfigurationDescriptor(transfer),
        @intFromEnum(DescriptorType.string) => return hubGetStringDescriptor(transfer),
        else => {
            log.warn("hubGetDescriptor: descriptor type {d} not supported", .{descriptor_type});
            return .unsupported_request;
        },
    }
}

fn hubGetConfiguration(transfer: *Transfer) TransferStatus {
    if (transfer.setup.data_size >= 1) {
        transfer.data_buffer[0] = 1;
    }
    return .ok;
}

fn hubSetConfiguration(transfer: *Transfer) TransferStatus {
    const requested_configuration = transfer.setup.value;
    if (requested_configuration == 1) {
        return .ok;
    } else {
        log.warn("hubSetConfiguration: requested configuration {d} not supported", .{requested_configuration});
        return .unsupported_request;
    }
}

fn hubGetHubDescriptor(transfer: *Transfer) TransferStatus {
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index == 0) {
        return replyWithStructure(transfer, &root_hub_hub_descriptor, @sizeOf(@TypeOf(root_hub_hub_descriptor)));
    } else {
        log.warn("hubGetHubDescriptor: descriptor index {d} not supported", .{descriptor_index});
        return .unsupported_request;
    }
}

fn hubGetHubStatus(transfer: *Transfer) TransferStatus {
    return replyWithStructure(transfer, &root_hub_hub_status, @sizeOf(@TypeOf(root_hub_hub_status)));
}

fn hubGetPortStatus(transfer: *Transfer) TransferStatus {
    return replyWithStructure(transfer, &root_hub_port_status, @sizeOf(@TypeOf(root_hub_port_status)));
}

fn hubSetHubFeature(_: *Transfer) TransferStatus {
    log.warn("hubSetHubFeature: set hub feature not supported", .{});
    return .unsupported_request;
}

fn hubSetPortFeature(transfer: *Transfer) TransferStatus {
    const feature = transfer.setup.value;

    switch (feature) {
        @intFromEnum(PortFeature.port_power) => return hostPortPowerOn(),
        @intFromEnum(PortFeature.port_reset) => return hostPortReset(),
        else => {
            log.warn("hubSetPortFeature: port feature {d} not supported", .{feature});
            return .unsupported_request;
        },
    }
}

fn hubClearHubFeature(_: *Transfer) TransferStatus {
    log.warn("hubClearHubFeature: clear hub feature not supported", .{});
    return .unsupported_request;
}

fn hubClearPortFeature(transfer: *Transfer) TransferStatus {
    const feature = transfer.setup.value;

    switch (feature) {
        @intFromEnum(PortFeature.c_port_connection) => root_hub_port_status.port_change.connected_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_enable) => root_hub_port_status.port_change.enabled_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_suspend) => root_hub_port_status.port_change.suspended_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_over_current) => root_hub_port_status.port_change.overcurrent_changed = .not_changed,
        @intFromEnum(PortFeature.c_port_reset) => root_hub_port_status.port_change.reset_changed = .not_changed,
        else => {
            log.warn("hubClearPortFeature: feature {d} not supported", .{feature});
            return .unsupported_request;
        },
    }
    return .ok;
}

pub fn hubHandleTransfer(transfer: *Transfer) !void {
    switch (transfer.transfer_type) {
        .control => {
            const req_type = transfer.setup.request_type.type;
            const request = transfer.setup.request;
            const recipient = transfer.setup.request_type.recipient;

            for (handlers) |h| {
                if (req_type == h[0] and (h[1] == null or h[1] == request) and (h[2] == null or h[2] == recipient)) {
                    transfer.complete(h[3](transfer));
                    return;
                }
            }
        },
        else => {
            log.warn("hubHandleTransfer: transfer type {d} not supported", .{transfer.transfer_type});
            transfer.complete(.unsupported_request);
        },
    }
}

// ----------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

fn expectTransferStatus(expected_status: TransferStatus, xfer: *Transfer) !void {
    try hubHandleTransfer(xfer);
    try expectEqual(expected_status, xfer.status);
}

test "only control transfers are supported" {
    std.debug.print("\n", .{});

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

    try expectTransferStatus(.unsupported_request, &iso);
    try expectTransferStatus(.unsupported_request, &bulk);
    try expectTransferStatus(.unsupported_request, &interrupt);
}

test "get device descriptor" {
    std.debug.print("\n", .{});

    const buffer_size = @sizeOf(DeviceDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.device, 0, 0, @sizeOf(DeviceDescriptor)),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);

    const device_descriptor = std.mem.bytesAsValue(DeviceDescriptor, xfer.data_buffer[0..@sizeOf(DeviceDescriptor)]);

    try expectEqual(DescriptorType.device, device_descriptor.header.descriptor_type);
    try expectEqual(@as(u8, @intFromEnum(DeviceClass.hub)), device_descriptor.device_class);
    try expectEqual(@as(u8, 0), device_descriptor.device_subclass);
    try expectEqual(@as(u8, 0), device_descriptor.device_protocol);
    try expect(device_descriptor.configuration_count >= 1);
    try expect(device_descriptor.max_packet_size >= 8);
}

test "get device descriptor (with insufficient buffer length)" {
    std.debug.print("\n", .{});

    const short_buffer_len: u16 = @as(u16, @sizeOf(DeviceDescriptor)) / 2;
    var buffer: [short_buffer_len]u8 = undefined;

    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.device, 0, 0, short_buffer_len),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    try expectEqual(short_buffer_len, xfer.actual_size);
}

test "get configuration descriptor" {
    std.debug.print("\n", .{});

    const buffer_size = @sizeOf(ConfigurationDescriptor) + @sizeOf(InterfaceDescriptor) + @sizeOf(EndpointDescriptor);
    var buffer: [buffer_size]u8 = undefined;

    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.configuration, 1, 0, buffer_size),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);

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

test "get configuration descriptor (with insufficient buffer length)" {
    std.debug.print("\n", .{});

    const buffer_size = (@sizeOf(ConfigurationDescriptor) + @sizeOf(InterfaceDescriptor) + @sizeOf(EndpointDescriptor)) / 2;
    var buffer: [buffer_size]u8 = undefined;

    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.configuration, 1, 0, buffer_size),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "get string descriptors" {
    std.debug.print("\n", .{});

    // Should be a descriptor header plus a single u16
    const buffer_size = @sizeOf(usb.StringDescriptor);
    var buffer: [buffer_size]u8 align(2) = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.string, 0, 0, buffer_size),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    const string = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data_buffer[0..buffer_size])));

    try expectEqualSlices(u16, &.{0x0409}, string.body[0..1]);

    // check string at index 1
    xfer.setup = usb.setupDescriptorQuery(.string, 1, 0, buffer_size);

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    const string2 = @as(*align(2) StringDescriptor, @ptrCast(@alignCast(xfer.data_buffer[0..buffer_size])));
    const str_slice = try string2.asSlice(std.testing.allocator);
    defer std.testing.allocator.free(str_slice);

    try expectEqualSlices(u8, "USB", str_slice[0..3]);
}

test "get string descriptor (with insufficient buffer length)" {
    std.debug.print("\n", .{});

    const buffer_size = @sizeOf(usb.Header) + 4;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupDescriptorQuery(.string, 1, 0, buffer_size),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "get status (standard request)" {
    std.debug.print("\n", .{});

    const buffer_size = @sizeOf(u16);
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetStatus(),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try hubHandleTransfer(&xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "we support 'set configuration' if the chosen configuration is 1" {
    std.debug.print("\n", .{});

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetConfiguration(1),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);
}

test "we do not support 'set configuration' if the chosen configuration is not 1" {
    std.debug.print("\n", .{});

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetConfiguration(99),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.unsupported_request, &xfer);
}

test "'get configuration' always returns 1" {
    std.debug.print("\n", .{});

    const buffer_size = 1;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetConfiguration(),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u8, buffer_size), xfer.data_buffer[0]);
}

test "get descriptor (class request)" {
    std.debug.print("\n", .{});

    const buffer_size = @sizeOf(HubDescriptor);
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetHubDescriptor(0, buffer_size),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);

    const hub_descriptor = std.mem.bytesAsValue(HubDescriptor, xfer.data_buffer[0..@sizeOf(HubDescriptor)]);

    try expectEqual(DescriptorType.hub, hub_descriptor.header.descriptor_type);
    try expectEqual(@as(u8, 1), hub_descriptor.number_ports);
}

test "get hub status (class request)" {
    std.debug.print("\n", .{});

    const buffer_size = 4;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetHubStatus(),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "get port status (class request)" {
    std.debug.print("\n", .{});

    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetPortStatus(1),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

fn getPortPowerStatus() !bool {
    const buffer_size = @sizeOf(PortStatus);
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupGetPortStatus(1),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);

    const port_status = std.mem.bytesAsValue(PortStatus, xfer.data_buffer[0..@sizeOf(PortStatus)]);

    return port_status.port_status.power == .on;
}

fn fakeRegisters() registers.HostRegisters {
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

test "set port feature (class request) power" {
    std.debug.print("\n", .{});

    var regs = fakeRegisters();
    host_registers = &regs;

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetPortFeature(PortFeature.port_power, 1, 0),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "set port feature (class request) reset" {
    std.debug.print("\n", .{});

    var regs = fakeRegisters();
    host_registers = &regs;

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetPortFeature(PortFeature.port_reset, 1, 0),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "we silently support 'set address'" {
    std.debug.print("\n", .{});

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetAddress(123),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.ok, &xfer);

    try expectEqual(@as(u16, buffer_size), xfer.actual_size);
}

test "we don't support 'set hub feature'" {
    std.debug.print("\n", .{});

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupSetHubFeature(.c_hub_local_power),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.unsupported_request, &xfer);
}

test "we don't support 'clear hub feature'" {
    std.debug.print("\n", .{});

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    var xfer: Transfer = .{
        .transfer_type = .control,
        .setup = usb.setupClearHubFeature(.c_hub_local_power),
        .data_buffer = &buffer,
    };

    try expectTransferStatus(.unsupported_request, &xfer);
}
