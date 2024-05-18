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
const StringDescriptor = usb.StringDescriptor;
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferStatus = usb.TransferRequest.CompletionStatus;
const TransferFactory = usb.TransferFactory;
const TransferType = usb.TransferType;

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
root_hub_status_change_transfer: ?*TransferRequest = null,
root_hub_configuration: u8 = 1,

port_connect_status_changed: bool = false,
port_enabled_changed: bool = false,
port_overcurrent_changed: bool = false,

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

const root_hub_configuration_descriptor: RootHubConfiguration = .{
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

pub const root_hub_hub_descriptor_base: usb.HubDescriptor = .{
    .length = @sizeOf(usb.HubDescriptor) + 2,
    .descriptor_type = usb.USB_DESCRIPTOR_TYPE_HUB,
    .number_ports = 1,
    .characteristics = @bitCast(@as(u16, 0)),
    .power_on_to_power_good = 0,
    .controller_current = 1,
};

const root_hub_hub_descriptor: RootHubDescriptor = .{
    .base = root_hub_hub_descriptor_base,
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

fn hostPortDisable(self: *Self) usb.URB.Status {
    if (self.host_registers) |host_reg| {
        Host.log.debug(@src(), "hostPortDisable", .{});

        var hw_status = self.hostPortSafeRead(host_reg);

        hw_status.enabled = 0;

        host_reg.port = hw_status;
    }
    return .OK;
}

fn hostPortPowerOn(self: *Self) usb.URB.Status {
    if (self.host_registers) |host_reg| {
        Host.log.debug(@src(), "hostPortPowerOn", .{});

        var hw_status = self.hostPortSafeRead(host_reg);

        hw_status.power = 1;

        host_reg.port = hw_status;
    }
    return .OK;
}

fn hostPortPowerOff(self: *Self) usb.URB.Status {
    if (self.host_registers) |host_reg| {
        var hw_status = self.hostPortSafeRead(host_reg);

        hw_status.power = 0;

        host_reg.port = hw_status;
    }
    return .OK;
}

fn hostPortReset(self: *Self) usb.URB.Status {
    const regs = self.host_registers orelse return .Failed;

    var port = self.hostPortSafeRead(regs);

    // assert the reset bit
    port.reset = 1;
    regs.port = port;

    // wait for it to be processed
    delayMillis(100);

    // deassert the reset bit
    port.reset = 0;
    regs.port = port;

    // wait for it to be processed
    delayMillis(100);

    // we should see enabled go high within a short time.
    const enable_wait_end = time.deadlineMillis(200);
    while (regs.port.enabled == 0 and time.ticks() < enable_wait_end) {
        delayMillis(10);
    }

    if (regs.port.enabled == 0) {
        Host.log.err(@src(), "port enabled bit not observed before timeout", .{});
        return .Failed;
    }

    return .OK;
}

// ----------------------------------------------------------------------
// Interrupt Handler
// ----------------------------------------------------------------------

// This is called from the DWC core driver when it receives a 'port'
// interrupt
pub fn hubHandlePortInterrupt(self: *Self) void {
    const regs = self.host_registers orelse return;
    const port = regs.port;
    var port_dup = port;
    port_dup.overcurrent_changed = 0;
    port_dup.connected_changed = 0;
    port_dup.enabled_changed = 0;
    port_dup.enabled = 0;

    Host.log.debug(@src(), "host port interrupt, port 0x{x:0>8}", .{@as(u32, @bitCast(port))});

    if (port.connected_changed != 0) {
        if (port.connected != 0) {
            // indicate port status change of port 1 (which is bit 1 == 0x02)
            usb.root_hub.status_change_buffer[0] = 0x2;
            usb.hubThreadWakeup(usb.root_hub);
        }
        port_dup.connected_changed = 1; // write-clear this status bit
        self.port_connect_status_changed = true;
    }

    if (port.enabled_changed != 0) {
        port_dup.enabled_changed = 1; // write-clear this status bit
        self.port_enabled_changed = true;

        // TODO - do we need to perform speed detection here?
    }

    if (port.overcurrent_changed != 0) {
        port_dup.overcurrent_changed = 1; // write-clear this status bit
        self.port_overcurrent_changed = true;
    }

    // Clear the interrupts by writing the modified control register value back
    regs.port = port_dup;
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
fn getPortSpeed(self: *Self) u8 {
    return switch (self.host_registers.?.port.speed) {
        .high => usb.USB_SPEED_HIGH,
        .full => usb.USB_SPEED_FULL,
        .low => usb.USB_SPEED_LOW,
        .undefined => usb.USB_SPEED_UNKNOWN,
    };
}

fn replyWithStructure(setup: *usb.SetupPacket, out: []u8, data: []const u8) usb.URB.Status {
    _ = setup;
    const actual_length = @min(out.len, data.len);
    Host.log.debug(@src(), "responding with {d} bytes from 0x{x:0>8}", .{ actual_length, @intFromPtr(data.ptr) });
    Host.log.sliceDump(@src(), data[0..actual_length]);
    @memcpy(out[0..actual_length], data[0..actual_length]);
    return .OK;
}

// zig fmt: off
inline fn deviceRequest(rt: u8)   bool { return rt & 0x1f == usb.REQUEST_RECIPIENT_DEVICE; }
inline fn otherRequest(rt: u8)    bool { return rt & 0x1f == usb.REQUEST_RECIPIENT_OTHER; }
inline fn standardRequest(rt: u8) bool { return rt & 0x60 == usb.REQUEST_TYPE_STANDARD; }
inline fn classRequest(rt: u8)    bool { return rt & 0x60 == usb.REQUEST_TYPE_CLASS; }
// zig fmt: on

pub fn control(self: *Self, setup: *usb.SetupPacket, data: ?[]u8) usb.URB.Status {
    Host.log.debug(@src(), "processing control message, req_type 0x{x:0>2}, req 0x{x:0>2}", .{ setup.request_type, setup.request });
    Host.log.sliceDump(@src(), std.mem.asBytes(setup));

    const port = setup.index;

    if (deviceRequest(setup.request_type)) {
        switch (setup.request) {
            usb.HUB_REQUEST_CLEAR_FEATURE => {
                switch (setup.value) {
                    usb.USB_HUB_FEATURE_C_LOCAL_POWER => return .OK,
                    usb.USB_HUB_FEATURE_C_OVERCURRENT => return .OK,
                    else => return .NotSupported,
                }
            },
            usb.HUB_REQUEST_SET_FEATURE => {
                switch (setup.value) {
                    usb.USB_HUB_FEATURE_C_LOCAL_POWER => return .OK,
                    usb.USB_HUB_FEATURE_C_OVERCURRENT => return .OK,
                    else => return .NotSupported,
                }
            },
            usb.USB_REQUEST_SET_ADDRESS => return .OK,
            usb.USB_REQUEST_SET_CONFIGURATION => {
                self.root_hub_configuration = @truncate(setup.value & 0xff);
                return .OK;
            },
            usb.USB_REQUEST_GET_DESCRIPTOR => {
                const descriptor_type = setup.value >> 8;

                if (standardRequest(setup.request_type)) {
                    switch (descriptor_type) {
                        usb.USB_DESCRIPTOR_TYPE_DEVICE => {
                            return replyWithStructure(setup, data.?, std.mem.asBytes(&root_hub_device_descriptor));
                        },
                        usb.USB_DESCRIPTOR_TYPE_CONFIGURATION => {
                            return replyWithStructure(setup, data.?, std.mem.asBytes(&root_hub_configuration_descriptor));
                        },
                        usb.USB_DESCRIPTOR_TYPE_STRING => {
                            const string_index = setup.value & 0xf;
                            if (string_index < root_hub_strings.len) {
                                return replyWithStructure(setup, data.?, std.mem.asBytes(&root_hub_strings[string_index]));
                            } else {
                                return .Failed;
                            }
                        },
                        else => return .NotSupported,
                    }
                } else if (classRequest(setup.request_type)) {
                    switch (descriptor_type) {
                        usb.USB_DESCRIPTOR_TYPE_HUB => {
                            return replyWithStructure(setup, data.?, std.mem.asBytes(&root_hub_hub_descriptor));
                        },
                        else => return .NotSupported,
                    }
                } else {
                    return .Failed;
                }
            },
            usb.HUB_REQUEST_GET_STATUS => {
                return replyWithStructure(setup, data.?, std.mem.asBytes(&self.root_hub_hub_status));
            },
            usb.USB_REQUEST_GET_CONFIGURATION => {
                return replyWithStructure(setup, data.?, std.mem.asBytes(&self.root_hub_configuration));
            },
            else => return .NotSupported,
        }
    } else if (otherRequest(setup.request_type)) {
        switch (setup.request) {
            usb.HUB_REQUEST_CLEAR_FEATURE => {
                Host.log.debug(@src(), "port {d} feature clear {d}", .{ port, setup.value });
                if (port != 1) {
                    return .Failed;
                }

                switch (setup.value) {
                    usb.HUB_PORT_FEATURE_PORT_ENABLE => return self.hostPortDisable(),
                    usb.HUB_PORT_FEATURE_PORT_POWER => return self.hostPortPowerOff(),
                    usb.HUB_PORT_FEATURE_C_PORT_CONNECTION => {
                        self.port_connect_status_changed = false;
                        return .OK;
                    },
                    usb.HUB_PORT_FEATURE_C_PORT_ENABLE => {
                        self.port_enabled_changed = false;
                        return .OK;
                    },
                    usb.HUB_PORT_FEATURE_C_PORT_OVER_CURRENT => {
                        self.port_overcurrent_changed = false;
                        return .OK;
                    },
                    else => return .OK,
                }
            },
            usb.HUB_REQUEST_GET_STATUS => {
                if (port != 1) {
                    return .Failed;
                }

                var status: u32 = 0;
                if (self.port_connect_status_changed) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_C_PORT_CONNECTION;
                }
                if (self.port_enabled_changed) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_C_PORT_ENABLE;
                }
                if (self.port_overcurrent_changed) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_C_PORT_OVER_CURRENT;
                }

                const port_control: reg.HostPortStatusAndControl = self.host_registers.?.port;
                Host.log.debug(@src(), "hub_request_get_status, port status is 0x{x:0>8}", .{@as(u32, @bitCast(port_control))});

                if (port_control.connected != 0) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_CONNECTION;
                }

                if (port_control.enabled != 0) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_ENABLE;

                    const speed = self.getPortSpeed();
                    if (speed == usb.USB_SPEED_LOW) {
                        status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_LOW_SPEED;
                    } else if (speed == usb.USB_SPEED_HIGH) {
                        status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_HIGH_SPEED;
                    }
                }
                if (port_control.overcurrent != 0) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_OVER_CURRENT;
                }
                if (port_control.reset != 0) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_RESET;
                }
                if (port_control.power != 0) {
                    status |= @as(u32, 1) << usb.HUB_PORT_FEATURE_PORT_POWER;
                }
                return replyWithStructure(setup, data.?, std.mem.asBytes(&status));
            },
            usb.HUB_REQUEST_SET_FEATURE => {
                if (port != 1) {
                    return .Failed;
                }

                switch (setup.value) {
                    usb.HUB_PORT_FEATURE_PORT_POWER => return self.hostPortPowerOn(),
                    usb.HUB_PORT_FEATURE_PORT_RESET => return self.hostPortReset(),
                    //                    usb.HUB_PORT_FEATURE_PORT_SUSPEND => return .OK,
                    else => return .OK,
                }
            },
            else => return .NotSupported,
        }
    } else {
        return .NotSupported;
    }
}
