const std = @import("std");
const log = std.log.scoped(.dwc_otg_usb);

const time = @import("../../time.zig");
const delayMillis = time.delayMillis;

const usb = @import("../../usb.zig");
const ClassRequestCode = usb.ClassRequestCode;
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DescriptorType = usb.DescriptorType;
const DeviceClass = usb.DeviceClass;
const DeviceConfiguration = usb.DeviceConfiguration;
const DeviceDescriptor = usb.DeviceDescriptor;
const DeviceStatus = usb.DeviceStatus;
const EndpointDescriptor = usb.EndpointDescriptor;
const HubClassRequest = usb.hub.ClassRequest;
const HubDescriptor = usb.HubDescriptor;
const HubStatus = usb.HubStatus;
const InterfaceClass = usb.InterfaceClass;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const LangID = usb.LangID;
const PortFeature = usb.PortFeature;
const PortStatus = usb.PortStatus;
const RequestTypeRecipient = usb.RequestTypeRecipient;
const RequestTypeType = usb.RequestTypeType;
const StandardDeviceRequests = usb.StandardDeviceRequests;
const StringDescriptor = usb.StringDescriptor;
const Transfer = usb.Transfer;
const TransferBytes = usb.TransferBytes;
const TransferStatus = usb.TransferCompletionStatus;
const TransferFactory = usb.TransferFactory;

const reg = @import("registers.zig");
const HostPortStatusAndControl = reg.HostPortStatusAndControl;
const HostRegisters = reg.HostRegisters;

const Self = @This();

// ----------------------------------------------------------------------
// Mutable state
// ----------------------------------------------------------------------
host_registers: ?*volatile reg.HostRegisters = null,

root_hub_device_status: DeviceStatus = usb.STATUS_SELF_POWERED,

root_hub_hub_status: HubStatus = .{
    .hub_status = .{
        .local_power_source = 1,
        .overcurrent = 0,
    },
    .change_status = .{
        .local_power_changed = 0,
        .overcurrent_changed = 0,
    },
},

root_hub_port_status: PortStatus = .{
    .port_status = @bitCast(@as(u16, 0)),
    .port_change = @bitCast(@as(u16, 0)),
},

root_hub_status_change_transfer: ?*Transfer = null,

pub fn init(self: *Self, registers: *volatile HostRegisters) void {
    self.* = .{
        .host_registers = registers,
    };
}

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
    .product_name = 1,
    .serial_number = 0,
    .configuration_count = 1,
};

const RootHubConfiguration = packed struct {
    configuration: ConfigurationDescriptor,
    interface: InterfaceDescriptor,
    endpoint: EndpointDescriptor,
};

const root_hub_configuration: RootHubConfiguration = .{
    .configuration = .{
        .header = .{
            .length = ConfigurationDescriptor.STANDARD_LENGTH,
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
            .length = InterfaceDescriptor.STANDARD_LENGTH,
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
            .length = EndpointDescriptor.STANDARD_LENGTH,
            .descriptor_type = .endpoint,
        },
        .endpoint_address = (1 << 7) | 1,
        .attributes = .{
            .transfer_type = .interrupt,
            .iso_synch_type = .none,
            .usage_type = .data,
        },
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

fn hostPortSafeRead(self: *Self, host_reg: *volatile reg.HostRegisters) HostPortStatusAndControl {
    _ = self;
    var hw_status = host_reg.port;

    // We zero out some bits because they are "write clear" and we
    // could accidentally reset them if they read as 1
    hw_status.enabled = 0;
    hw_status.connect_changed = 0;
    hw_status.enabled_changed = 0;
    hw_status.overcurrent_changed = 0;

    return hw_status;
}

fn hostPortPowerOn(self: *Self) TransferStatus {
    if (self.host_registers) |host_reg| {
        log.debug("hostPortPowerOn", .{});

        var hw_status = self.hostPortSafeRead(host_reg);

        hw_status.power = 1;

        host_reg.port = hw_status;
    }
    return .ok;
}

fn hostPortPowerOff(self: *Self) TransferStatus {
    if (self.host_registers) |host_reg| {
        var hw_status = self.hostPortSafeRead(host_reg);

        hw_status.power = 0;

        host_reg.port = hw_status;
    }
    return .ok;
}

fn hostPortReset(self: *Self) TransferStatus {
    if (self.host_registers) |host_reg| {
        var hw_status = self.hostPortSafeRead(host_reg);
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
pub fn hubHandlePortInterrupt(self: *Self) void {
    if (self.host_registers) |host_reg| {
        var hw_status = host_reg.port;

        self.root_hub_port_status.port_status.connected = hw_status.connect;
        self.root_hub_port_status.port_status.enabled = hw_status.enabled;
        self.root_hub_port_status.port_status.suspended = hw_status.status_suspend;
        self.root_hub_port_status.port_status.overcurrent = hw_status.overcurrent;
        self.root_hub_port_status.port_status.reset = hw_status.reset;
        self.root_hub_port_status.port_status.power = hw_status.power;
        self.root_hub_port_status.port_status.low_speed_device = if (hw_status.speed == .low) 1 else 0;
        self.root_hub_port_status.port_status.high_speed_device = if (hw_status.speed == .high) 1 else 0;

        self.root_hub_port_status.port_change.connected_changed = hw_status.connect_changed;
        self.root_hub_port_status.port_change.enabled_changed = hw_status.enabled_changed;
        self.root_hub_port_status.port_change.overcurrent_changed = hw_status.overcurrent_changed;

        // Clear the interrupts, which are WC ("write clear") bits by
        // writing the register value back to itself, except for the
        // enabled bit!
        hw_status.enabled = 0;
        host_reg.port = hw_status;

        self.hubNotifyPortChange();
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

fn hubNotifyPortChange(self: *Self) void {
    if (self.root_hub_status_change_transfer) |request| {
        log.debug("root hub completing pending interrupt transfer", .{});
        self.root_hub_status_change_transfer = null;
        if (request.data_buffer.len >= 1) {
            // in the status change, bit 0 indicates the hub changed,
            // bits 1..N indicate a port change. We pretend the DWC
            // host port is port 1, so we set bit 1 in the one-byte
            // response.
            //
            // See USB specification, revision 2.0 dated April 2000,
            // section 11.12.4
            request.data_buffer[0] = 0x02;
            request.actual_size = 1;
        } else {
            request.actual_size = 0;
        }
        request.complete(.ok);
    }
}

// ----------------------------------------------------------------------
// Request Handling Behavior
// ----------------------------------------------------------------------
const Handler = struct { RequestTypeType, ?u8, ?usb.RequestTypeRecipient, *const fn (self: *Self, transfer: *Transfer) TransferStatus };

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
    log.debug("responding with {d} bytes from the structure", .{provided_length});
    @memcpy(transfer.data_buffer[0..provided_length], @as([*]const u8, @ptrCast(v))[0..provided_length]);
    transfer.actual_size = provided_length;
    return .ok;
}

fn hubGetDeviceDescriptor(self: *Self, transfer: *Transfer) TransferStatus {
    _ = self;
    return replyWithStructure(transfer, &root_hub_device_descriptor, @sizeOf(@TypeOf(root_hub_device_descriptor)));
}

fn hubGetConfigurationDescriptor(self: *Self, transfer: *Transfer) TransferStatus {
    _ = self;
    return replyWithStructure(transfer, &root_hub_configuration, @sizeOf(@TypeOf(root_hub_configuration)));
}

fn hubGetStringDescriptor(self: *Self, transfer: *Transfer) TransferStatus {
    _ = self;
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index > root_hub_strings.len) {
        log.warn("hubGetStringDescriptor: descriptor_index {d} is greater than {d}", .{ descriptor_index, root_hub_strings.len });
        return .unsupported_request;
    }

    const string = &root_hub_strings[descriptor_index];
    return replyWithStructure(transfer, string, string.header.length);
}

fn hubGetDeviceStatus(self: *Self, transfer: *Transfer) TransferStatus {
    return replyWithStructure(transfer, &self.root_hub_device_status, @sizeOf(@TypeOf(self.root_hub_device_status)));
}

fn hubSetAddress(_: *Self, _: *Transfer) TransferStatus {
    return .ok;
}

fn hubGetDescriptor(self: *Self, transfer: *Transfer) TransferStatus {
    const descriptor_type = transfer.setup.value >> 8;
    switch (descriptor_type) {
        @intFromEnum(DescriptorType.device) => return self.hubGetDeviceDescriptor(transfer),
        @intFromEnum(DescriptorType.configuration) => return self.hubGetConfigurationDescriptor(transfer),
        @intFromEnum(DescriptorType.string) => return self.hubGetStringDescriptor(transfer),
        else => {
            log.warn("hubGetDescriptor: descriptor type {d} not supported", .{descriptor_type});
            return .unsupported_request;
        },
    }
}

fn hubGetConfiguration(self: *const Self, transfer: *Transfer) TransferStatus {
    _ = self;
    if (transfer.setup.data_size >= 1) {
        transfer.data_buffer[0] = 1;
    }
    return .ok;
}

fn hubSetConfiguration(self: *Self, transfer: *Transfer) TransferStatus {
    _ = self;
    const requested_configuration = transfer.setup.value;
    if (requested_configuration == 1) {
        log.debug("hubSetConfiguration: using requested configuration {d}", .{requested_configuration});
        return .ok;
    } else {
        log.warn("hubSetConfiguration: requested configuration {d} not supported", .{requested_configuration});
        return .unsupported_request;
    }
}

fn hubGetHubDescriptor(self: *Self, transfer: *Transfer) TransferStatus {
    _ = self;
    const descriptor_index = transfer.setup.value & 0x0f;
    if (descriptor_index == 0) {
        return replyWithStructure(transfer, &root_hub_hub_descriptor, @sizeOf(@TypeOf(root_hub_hub_descriptor)));
    } else {
        log.warn("hubGetHubDescriptor: descriptor index {d} not supported", .{descriptor_index});
        return .unsupported_request;
    }
}

fn hubGetHubStatus(self: *Self, transfer: *Transfer) TransferStatus {
    return replyWithStructure(transfer, &self.root_hub_hub_status, @sizeOf(@TypeOf(self.root_hub_hub_status)));
}

fn hubGetPortStatus(self: *Self, transfer: *Transfer) TransferStatus {
    log.debug("hubGetPortStatus: port {d}", .{transfer.setup.index});
    return replyWithStructure(transfer, &self.root_hub_port_status, @sizeOf(@TypeOf(self.root_hub_port_status)));
}

fn hubSetHubFeature(self: *Self, _: *Transfer) TransferStatus {
    _ = self;
    log.warn("hubSetHubFeature: set hub feature not supported", .{});
    return .unsupported_request;
}

fn hubSetPortFeature(self: *Self, transfer: *Transfer) TransferStatus {
    const feature = transfer.setup.value;

    switch (feature) {
        @intFromEnum(PortFeature.port_power) => return self.hostPortPowerOn(),
        @intFromEnum(PortFeature.port_reset) => return self.hostPortReset(),
        else => {
            log.warn("hubSetPortFeature: port feature {d} not supported", .{feature});
            return .unsupported_request;
        },
    }
}

fn hubClearHubFeature(self: *Self, _: *Transfer) TransferStatus {
    _ = self;
    log.warn("hubClearHubFeature: clear hub feature not supported", .{});
    return .unsupported_request;
}

fn hubClearPortFeature(self: *Self, transfer: *Transfer) TransferStatus {
    const feature = transfer.setup.value;

    switch (feature) {
        @intFromEnum(PortFeature.c_port_connection) => self.root_hub_port_status.port_change.connected_changed = 0,
        @intFromEnum(PortFeature.c_port_enable) => self.root_hub_port_status.port_change.enabled_changed = 0,
        @intFromEnum(PortFeature.c_port_suspend) => self.root_hub_port_status.port_change.suspended_changed = 0,
        @intFromEnum(PortFeature.c_port_over_current) => self.root_hub_port_status.port_change.overcurrent_changed = 0,
        @intFromEnum(PortFeature.c_port_reset) => self.root_hub_port_status.port_change.reset_changed = 0,
        else => {
            log.warn("hubClearPortFeature: feature {d} not supported", .{feature});
            return .unsupported_request;
        },
    }
    return .ok;
}

pub fn hubHandleTransfer(self: *Self, transfer: *Transfer) void {
    switch (transfer.endpoint_type) {
        .control => {
            const req_type = transfer.setup.request_type.type;
            const request = transfer.setup.request;
            const recipient = transfer.setup.request_type.recipient;

            for (handlers) |h| {
                if (req_type == h[0] and (h[1] == null or h[1] == request) and (h[2] == null or h[2] == recipient)) {
                    transfer.complete(h[3](self, transfer));
                    return;
                }
            }
        },
        .interrupt => {
            // assume this is for endpoint 1
            log.debug("hubHandleTransfer: holding interrupt transfer for when a status change happens", .{});
            self.root_hub_status_change_transfer = transfer;

            // we might have previously gotten a status change that we
            // need to report right now
            if (@as(u16, @bitCast(self.root_hub_port_status.port_change)) != 0) {
                self.hubNotifyPortChange();
            }
        },
        else => {
            log.warn("hubHandleTransfer: endpoint type {any} not supported", .{transfer.endpoint_type});
            transfer.complete(.unsupported_request);
        },
    }
}
