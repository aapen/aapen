const std = @import("std");

const Host = @import("../dwc_otg_usb.zig");

const time = @import("../../time.zig");
const delayMillis = time.delayMillis;

const usb = @import("../../usb.zig");
const ClassRequest = usb.ClassRequest;
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DeviceConfiguration = usb.DeviceConfiguration;
const DeviceDescriptor = usb.DeviceDescriptor;
const DeviceStatus = usb.DeviceStatus;
const EndpointDescriptor = usb.EndpointDescriptor;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const IsoSynchronizationType = usb.IsoSynchronizationType;
const RequestTypeRecipient = usb.RequestTypeRecipient;
const RequestTypeType = usb.RequestTypeType;
const StringDescriptor = usb.StringDescriptor;
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferStatus = usb.TransferRequest.CompletionStatus;
const TransferFactory = usb.TransferFactory;
const TransferType = usb.TransferType;

//const hub = @import("../../usb/hub.zig");

const reg = @import("registers.zig");
const HostPortStatusAndControl = reg.HostPortStatusAndControl;
const HostRegisters = reg.HostRegisters;

const Self = @This();

// ----------------------------------------------------------------------
// Mutable state
// ----------------------------------------------------------------------
host_registers: ?*volatile reg.HostRegisters = null,

root_hub_device_status: DeviceStatus = undefined,
root_hub_hub_status: usb.HubStatus = undefined,
root_hub_port_status: usb.PortStatus = undefined,
root_hub_status_change_transfer: ?*TransferRequest = null,

pub fn init(self: *Self, registers: *volatile HostRegisters) void {
    self.* = .{
        .host_registers = registers,
        .root_hub_device_status = usb.STATUS_SELF_POWERED,
        .root_hub_hub_status = .{
            .hub_status = .{
                .local_power_source = 1,
                .overcurrent = 0,
            },
            .change_status = .{
                .local_power_changed = 0,
                .overcurrent_changed = 0,
            },
        },
        .root_hub_port_status = .{
            .port_status = @bitCast(@as(u16, 0)),
            .port_change = @bitCast(@as(u16, 0)),
        },
    };
}

// ----------------------------------------------------------------------
// Static data
// ----------------------------------------------------------------------
const root_hub_device_descriptor: DeviceDescriptor = .{
    .length = @sizeOf(DeviceDescriptor),
    .descriptor_type = usb.USB_DESCRIPTOR_TYPE_DEVICE,
    .usb_standard_compliance = 0x200,
    .device_class = usb.USB_DEVICE_HUB,
    .device_subclass = 0,
    .device_protocol = 1,
    .max_packet_size = 64,
    .vendor = 0x1209, // see https://pid.codes
    .product = 0x0007, // see https://pid.codes
    .device_release = 0x0100,
    .manufacturer_name = 3,
    .product_name = 2,
    .serial_number = 1,
    .configuration_count = 1,
};

const RootHubConfiguration = packed struct {
    configuration: ConfigurationDescriptor,
    interface: InterfaceDescriptor,
    endpoint: EndpointDescriptor,
};

const root_hub_configuration: RootHubConfiguration = .{
    .configuration = .{
        .length = ConfigurationDescriptor.STANDARD_LENGTH,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_CONFIGURATION,
        .total_length = @sizeOf(RootHubConfiguration),
        .interface_count = 1,
        .configuration_value = 1,
        .configuration = 0,
        .attributes = 0xc0, // self-powered, no remote wakeup
        .power_max = 1,
    },
    .interface = .{
        .length = InterfaceDescriptor.STANDARD_LENGTH,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_INTERFACE,
        .interface_number = 0,
        .alternate_setting = 0,
        .endpoint_count = 1,
        .interface_class = usb.USB_INTERFACE_CLASS_HUB,
        .interface_subclass = 0,
        .interface_protocol = 1, // full speed hub
        .interface_string = 0,
    },
    .endpoint = .{
        .length = EndpointDescriptor.STANDARD_LENGTH,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_ENDPOINT,
        .endpoint_address = 0x81, // Endpoint 1, direction IN
        .attributes = TransferType.interrupt,
        .max_packet_size = 0x04,
        .interval = 0x0c,
    },
};

fn mkStringDescriptor(comptime payload: []const u16) StringDescriptor {
    if (payload.len > 31) @compileError("This unit only supports string descriptors up to 31 U16's long");

    var body: [31]u16 = [_]u16{0} ** 31;
    @memcpy(body[0..payload.len], payload);

    return .{
        .length = 2 + (2 * payload.len),
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_STRING,
        .body = body,
    };
}

const root_hub_default_language = mkStringDescriptor(&[_]u16{0x0409});
const root_hub_serial_number = mkStringDescriptor(&[_]u16{ '0', '0', '4', '2' });
const root_hub_product_name = mkStringDescriptor(&[_]u16{ 'A', 'a', 'p', 'e', 'n', ' ', 'U', 'S', 'B', ' ', '2', '.', '0', ' ', 'R', 'o', 'o', 't', ' ', 'H', 'u', 'b' });
const root_hub_manufacturer = mkStringDescriptor(&[_]u16{ 'M', '&', 'R', ' ', 'h', 'o', 'b', 'b', 'y', ' ', 's', 'h', 'o', 'p' });

// The order of these items must correspond to the indexes in the
// root_hub_device_descriptor
const root_hub_strings = &[_]StringDescriptor{
    root_hub_default_language,
    root_hub_serial_number,
    root_hub_product_name,
    root_hub_manufacturer,
};

const RootHubDescriptor = extern struct {
    base: usb.HubDescriptor,
    extra_data: [2]u8,
};

const root_hub_hub_descriptor: RootHubDescriptor = .{
    .base = .{
        .length = @sizeOf(usb.HubDescriptor) + 2,
        .descriptor_type = usb.USB_DESCRIPTOR_TYPE_HUB,
        .number_ports = 1,
        .characteristics = @bitCast(@as(u16, 0)),
        .power_on_to_power_good = 0,
        .controller_current = 1,
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
    hw_status.connected_changed = 0;
    hw_status.enabled_changed = 0;
    hw_status.overcurrent_changed = 0;

    return hw_status;
}

fn hostPortPowerOn(self: *Self) TransferStatus {
    if (self.host_registers) |host_reg| {
        Host.log.debug(@src(), "hostPortPowerOn", .{});

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

        Host.log.debug(@src(), "host port interrupt, hw_status = 0x{x:0>8}", .{@as(u32, @bitCast(hw_status))});

        self.root_hub_port_status.port_status.connected = hw_status.connected;
        self.root_hub_port_status.port_status.enabled = hw_status.enabled;
        self.root_hub_port_status.port_status.suspended = hw_status.suspended;
        self.root_hub_port_status.port_status.overcurrent = hw_status.overcurrent;
        self.root_hub_port_status.port_status.reset = hw_status.reset;
        self.root_hub_port_status.port_status.power = hw_status.power;
        self.root_hub_port_status.port_status.low_speed_device = if (hw_status.speed == .low) 1 else 0;
        self.root_hub_port_status.port_status.high_speed_device = if (hw_status.speed == .high) 1 else 0;

        self.root_hub_port_status.port_change.connected_changed = hw_status.connected_changed;
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
        Host.log.debug(@src(), "host port status changed; completing status changed transfer on root hub", .{});
        self.root_hub_status_change_transfer = null;
        if (request.size >= 1) {
            // in the status change, bit 0 indicates the hub changed,
            // bits 1..N indicate a port change. We pretend the DWC
            // host port is port 1, so we set bit 1 in the one-byte
            // response.
            //
            // See USB specification, revision 2.0 dated April 2000,
            // section 11.12.4
            request.data[0] = 0x02;
        }
        request.actual_size = 1;
        request.complete(.ok);
    }
}

// ----------------------------------------------------------------------
// Request Handling Behavior
// ----------------------------------------------------------------------
const Handler = struct { u2, ?u8, ?u5, *const fn (self: *Self, req: *TransferRequest) TransferStatus };

// null means "don't care", ignore this field when dispatching.

const handlers: []const Handler = &.{
    .{ RequestTypeType.standard, usb.USB_REQUEST_GET_STATUS, null, hubGetDeviceStatus },
    .{ RequestTypeType.standard, usb.USB_REQUEST_SET_ADDRESS, null, hubSetAddress },
    .{ RequestTypeType.standard, usb.USB_REQUEST_GET_DESCRIPTOR, null, hubGetDescriptor },
    .{ RequestTypeType.standard, usb.USB_REQUEST_GET_CONFIGURATION, null, hubGetConfiguration },
    .{ RequestTypeType.standard, usb.USB_REQUEST_SET_CONFIGURATION, null, hubSetConfiguration },
    .{ RequestTypeType.class, usb.HUB_REQUEST_GET_DESCRIPTOR, RequestTypeRecipient.device, hubGetHubDescriptor },
    .{ RequestTypeType.class, usb.HUB_REQUEST_GET_STATUS, RequestTypeRecipient.device, hubGetHubStatus },
    .{ RequestTypeType.class, usb.HUB_REQUEST_GET_STATUS, RequestTypeRecipient.other, hubGetPortStatus },
    .{ RequestTypeType.class, usb.HUB_REQUEST_SET_FEATURE, RequestTypeRecipient.device, hubSetHubFeature },
    .{ RequestTypeType.class, usb.HUB_REQUEST_SET_FEATURE, RequestTypeRecipient.other, hubSetPortFeature },
    .{ RequestTypeType.class, usb.HUB_REQUEST_CLEAR_FEATURE, RequestTypeRecipient.device, hubClearHubFeature },
    .{ RequestTypeType.class, usb.HUB_REQUEST_CLEAR_FEATURE, RequestTypeRecipient.other, hubClearPortFeature },
};

fn replyWithStructure(req: *TransferRequest, v: *const anyopaque, size: usize) TransferStatus {
    const requested_length = req.setup_data.data_size;
    const provided_length = @min(requested_length, size);
    Host.log.debug(@src(), "responding with {d} bytes from the structure", .{provided_length});
    @memcpy(req.data, @as([*]const u8, @ptrCast(v))[0..provided_length]);

    //    @memcpy(req.data_buffer[0..provided_length], @as([*]const u8, @ptrCast(v))[0..provided_length]);

    req.actual_size = provided_length;
    return .ok;
}

fn hubGetDeviceDescriptor(self: *Self, req: *TransferRequest) TransferStatus {
    _ = self;
    return replyWithStructure(req, &root_hub_device_descriptor, @sizeOf(@TypeOf(root_hub_device_descriptor)));
}

fn hubGetConfigurationDescriptor(self: *Self, req: *TransferRequest) TransferStatus {
    _ = self;
    return replyWithStructure(req, &root_hub_configuration, @sizeOf(@TypeOf(root_hub_configuration)));
}

fn hubGetStringDescriptor(self: *Self, req: *TransferRequest) TransferStatus {
    _ = self;
    const descriptor_index = req.setup_data.value & 0x0f;
    if (descriptor_index > root_hub_strings.len) {
        Host.log.warn(@src(), "hubGetStringDescriptor: descriptor_index {d} is greater than {d}", .{ descriptor_index, root_hub_strings.len });
        return .unsupported_request;
    }

    const string = &root_hub_strings[descriptor_index];
    return replyWithStructure(req, string, string.length);
}

fn hubGetDeviceStatus(self: *Self, req: *TransferRequest) TransferStatus {
    return replyWithStructure(req, &self.root_hub_device_status, @sizeOf(@TypeOf(self.root_hub_device_status)));
}

fn hubSetAddress(_: *Self, _: *TransferRequest) TransferStatus {
    return .ok;
}

fn hubGetDescriptor(self: *Self, req: *TransferRequest) TransferStatus {
    const descriptor_type = req.setup_data.value >> 8;
    switch (descriptor_type) {
        usb.USB_DESCRIPTOR_TYPE_DEVICE => return self.hubGetDeviceDescriptor(req),
        usb.USB_DESCRIPTOR_TYPE_CONFIGURATION => return self.hubGetConfigurationDescriptor(req),
        usb.USB_DESCRIPTOR_TYPE_STRING => return self.hubGetStringDescriptor(req),
        else => {
            Host.log.warn(@src(), "hubGetDescriptor: descriptor type {d} not supported", .{descriptor_type});
            return .unsupported_request;
        },
    }
}

fn hubGetConfiguration(self: *const Self, req: *TransferRequest) TransferStatus {
    _ = self;
    if (req.setup_data.data_size >= 1) {
        req.data[0] = 1;
    }
    return .ok;
}

fn hubSetConfiguration(self: *Self, req: *TransferRequest) TransferStatus {
    _ = self;
    const requested_configuration = req.setup_data.value;
    if (requested_configuration == 1) {
        Host.log.debug(@src(), "hubSetConfiguration: using requested configuration {d}", .{requested_configuration});
        return .ok;
    } else {
        Host.log.warn(@src(), "hubSetConfiguration: requested configuration {d} not supported", .{requested_configuration});
        return .unsupported_request;
    }
}

fn hubGetHubDescriptor(self: *Self, req: *TransferRequest) TransferStatus {
    _ = self;
    const descriptor_index = req.setup_data.value & 0x0f;
    if (descriptor_index == 0) {
        return replyWithStructure(req, &root_hub_hub_descriptor, @sizeOf(@TypeOf(root_hub_hub_descriptor)));
    } else {
        Host.log.warn(@src(), "hubGetHubDescriptor: descriptor index {d} not supported", .{descriptor_index});
        return .unsupported_request;
    }
}

fn hubGetHubStatus(self: *Self, req: *TransferRequest) TransferStatus {
    Host.log.debug(@src(), "hubGetHubStatus: status = 0x{x:0>8}", .{@as(u32, @bitCast(self.root_hub_hub_status))});
    return replyWithStructure(req, &self.root_hub_hub_status, @sizeOf(@TypeOf(self.root_hub_hub_status)));
}

fn hubGetPortStatus(self: *Self, req: *TransferRequest) TransferStatus {
    Host.log.debug(@src(), "hubGetPortStatus: port {d} status = 0x{x:0>8}", .{ req.setup_data.index, @as(u32, @bitCast(self.root_hub_port_status)) });
    return replyWithStructure(req, &self.root_hub_port_status, @sizeOf(@TypeOf(self.root_hub_port_status)));
}

fn hubSetHubFeature(self: *Self, _: *TransferRequest) TransferStatus {
    _ = self;
    Host.log.warn(@src(), "hubSetHubFeature: set hub feature not supported", .{});
    return .unsupported_request;
}

fn hubSetPortFeature(self: *Self, req: *TransferRequest) TransferStatus {
    const feature = req.setup_data.value;

    switch (feature) {
        usb.HUB_PORT_FEATURE_PORT_POWER => return self.hostPortPowerOn(),
        usb.HUB_PORT_FEATURE_PORT_RESET => return self.hostPortReset(),
        else => {
            Host.log.warn(@src(), "hubSetPortFeature: port feature {d} not supported", .{feature});
            return .unsupported_request;
        },
    }
}

fn hubClearHubFeature(self: *Self, _: *TransferRequest) TransferStatus {
    _ = self;
    Host.log.warn(@src(), "hubClearHubFeature: clear hub feature not supported", .{});
    return .unsupported_request;
}

fn hubClearPortFeature(self: *Self, req: *TransferRequest) TransferStatus {
    const feature = req.setup_data.value;

    Host.log.debug(@src(), "hubClearPortFeature: feature {d}", .{feature});

    switch (feature) {
        usb.HUB_PORT_FEATURE_C_PORT_CONNECTION => self.root_hub_port_status.port_change.connected_changed = 0,

        usb.HUB_PORT_FEATURE_C_PORT_ENABLE => self.root_hub_port_status.port_change.enabled_changed = 0,

        usb.HUB_PORT_FEATURE_C_PORT_SUSPEND => self.root_hub_port_status.port_change.suspended_changed = 0,

        usb.HUB_PORT_FEATURE_C_PORT_OVER_CURRENT => self.root_hub_port_status.port_change.overcurrent_changed = 0,

        usb.HUB_PORT_FEATURE_C_PORT_RESET => self.root_hub_port_status.port_change.reset_changed = 0,
        else => {
            Host.log.warn(@src(), "hubClearPortFeature: feature {d} not supported", .{feature});
            return .unsupported_request;
        },
    }
    return .ok;
}

pub fn hubHandleTransfer(self: *Self, req: *TransferRequest) void {
    if (req.endpoint_desc) |ep| {
        switch (ep.getType()) {
            TransferType.interrupt => {
                // this is an interrupt transfer request for the status change endpoint.
                Host.log.debug(@src(), "hubHandleTransfer: holding status change request a status change occurs", .{});
                self.root_hub_status_change_transfer = req;

                // we might have previously gotten a status change that we
                // need to report right now
                if (@as(u16, @bitCast(self.root_hub_port_status.port_change)) != 0) {
                    self.hubNotifyPortChange();
                }
            },
            else => {
                req.complete(.unsupported_request);
            },
        }
    } else {
        Host.log.debug(@src(), "hubHandleTransfer: processing control message", .{});

        // this is a control request to the default endpoint.
        const req_type = req.setup_data.request_type.type;
        const request = req.setup_data.request;
        const recipient = req.setup_data.request_type.recipient;

        for (handlers) |h| {
            if (req_type == h[0] and
                (h[1] == null or h[1] == request) and
                (h[2] == null or h[2] == recipient))
            {
                req.complete(h[3](self, req));
                return;
            }
        }
        Host.log.debug(@src(), "unhandled request: type 0x{x}, req 0x{x}", .{ @as(u8, @bitCast(req.setup_data.request_type)), request });
    }
}
