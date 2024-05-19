const std = @import("std");

const root = @import("root");
const HCI = root.HAL.USBHCI;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const schedule = @import("../schedule.zig");

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("../synchronize.zig");
const TicketLock = synchronize.TicketLock;

const hub = @import("hub.zig");
const spec = @import("spec.zig");

// ----------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------
var allocator: std.mem.Allocator = undefined;
var submitUrb: *const fn (urb: *URB) HCI.Error!URB.Status = undefined;
var rootHubControl: *const fn (setup: *spec.SetupPacket, data: ?[]u8) URB.Status = undefined;

pub fn initCore(alloc: std.mem.Allocator) void {
    log = Logger.init("usbc", .info);

    allocator = alloc;
    submitUrb = HCI.submitUrb;
    rootHubControl = HCI.rootHubControl;
}

pub const Error = error{
    Busy,
    ConfigurationError,
    DataLengthMismatch,
    DeviceDetaching,
    DeviceUnconfigured,
    DeviceUnsupported,
    Failed,
    HardwareError,
    IncorrectDevice,
    InitializationFailure,
    InvalidData,
    InvalidParameter,
    InvalidRequest,
    InvalidResponse,
    NoAvailableChannel,
    NoDevice,
    NotConnected,
    NotProcessed,
    OutOfMemory,
    OvercurrentDetected,
    PowerFailure,
    ResetTimeout,
    TooManyDevices,
    TooManyHubs,
    TransferFailed,
    TransferIncomplete,
    TransferStarted,
    TransferTimeout,
    UnsupportedRequest,
} || schedule.Error;

// ----------------------------------------------------------------------
// Transfer handling
// ----------------------------------------------------------------------
pub const URB = struct {
    pub const Completion = *const fn (self: *URB, actual_length: spec.TransferBytes) void;
    pub const Status = enum { OK, Busy, Failed, NotSupported };
    pub const StatusDetail = enum { OK, IO, Stall, Nak, Nyet, Babble, DataToggle };

    port: *hub.HubPort,
    ep: *spec.EndpointDescriptor,
    setup: ?*spec.SetupPacket,
    transfer_buffer: ?[*]u8,
    transfer_buffer_length: spec.TransferBytes,
    timeout: u16,
    complete: ?Completion = null,
    private: ?*anyopaque = null,
    actual_length: spec.TransferBytes = 0,
    status: Status = .OK,
    status_detail: StatusDetail = .OK,
    data_toggle: u1 = 0,

    pub inline fn fill(
        urb: *URB,
        port: *hub.HubPort,
        setup: *spec.SetupPacket,
        buffer: ?[]u8,
        buffer_length: spec.TransferBytes,
        timeout: u32,
        complete: ?Completion,
    ) void {
        const buf: ?[*]u8 = if (buffer != null) buffer.?.ptr else null;

        urb.* = .{
            .port = port,
            .ep = &port.ep0,
            .setup = setup,
            .transfer_buffer = buf,
            .transfer_buffer_length = buffer_length,
            .timeout = timeout,
            .complete = complete,
            .status = .OK,
            .status_detail = .OK,
        };
    }

    pub inline fn fillInterrupt(
        urb: *URB,
        port: *hub.HubPort,
        endpoint: *hub.Endpoint,
        buffer: ?[]u8,
        buffer_length: spec.TransferBytes,
        timeout: u32,
        complete: ?Completion,
    ) void {
        const buf: ?[*]u8 = if (buffer != null) buffer.?.ptr else null;

        urb.* = .{
            .port = port,
            .ep = &endpoint.ep_desc,
            .setup = null,
            .transfer_buffer = buf,
            .transfer_buffer_length = buffer_length,
            .timeout = timeout,
            .complete = complete,
            .status = .OK,
            .status_detail = .OK,
        };
    }

    pub fn isSynchronous(self: *const URB) bool {
        return self.complete == null;
    }

    pub fn callCompletion(self: *URB) void {
        if (self.complete) |c| {
            c(self, self.actual_length);
        }
    }
};

// ----------------------------------------------------------------------
// Specific transfers
// ----------------------------------------------------------------------
pub fn controlTransfer(port: *hub.HubPort, setup: *spec.SetupPacket, data: ?[]u8) !spec.TransferBytes {
    var urb = &port.ep0_urb;

    try semaphore.wait(port.mutex);
    defer semaphore.signal(port.mutex) catch {};

    var urb_slice = std.mem.asBytes(urb);
    @memset(urb_slice, 0);

    urb.fill(port, setup, data, setup.data_size, 0, null);
    const ret = try submitUrb(urb);

    log.debug(@src(), "submitUrb ret {s}", .{@tagName(ret)});

    if (ret == .OK) {
        return urb.actual_length;
    } else {
        return error.Failed;
    }
}

pub fn interruptTransfer(urb: *URB) !spec.TransferBytes {
    const ret = try submitUrb(urb);

    if (ret == .OK) {
        return urb.actual_length;
    } else if (!urb.isSynchronous() and ret == .Busy) {
        return 0;
    } else if (urb.status_detail == .Nak) {
        // NAK is normal for an interrupt request.
        return 0;
    } else {
        log.err(@src(), "dev addr {d} ep addr {d} interrupt transfer failed {}:{}", .{ urb.port.device_address, urb.ep.endpoint_address, urb.status, urb.status_detail });
        return error.Failed;
    }
}
