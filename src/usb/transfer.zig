const std = @import("std");

const device = @import("device.zig");
const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
const DeviceAddress = device.DeviceAddress;
const Device = device.Device;

const schedule = @import("../schedule.zig");
const TID = schedule.TID;
const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const spec = @import("spec.zig");
const TransferBytes = spec.TransferBytes;
const TransferPackets = spec.TransferPackets;

const status = @import("status.zig");
const TransactionStatus = status.TransactionStatus;

pub const DEFAULT_MAX_PACKET_SIZE = 8;

/// Describe a single USB transfer to perform. May be any type of
/// transfer, but if it is a control transfer then the setup member
/// must be filled in.
///
/// A Transfer usually consists of multiple stages, each called a
/// Transaction. On completion of a Transaction, the transfer may
/// continue with the next stage or, if the transaction had a problem,
/// may indicate a retry or may report failure.
pub const TransferRequest = struct {
    pub const Completion = *const fn (self: *TransferRequest) void;

    pub const CompletionStatus = enum {
        incomplete,
        ok,
        unsupported_request,
        timeout,
        protocol_error,
        failed,
    };

    pub const control_setup_phase: u8 = 0;
    pub const control_data_phase: u8 = 1;
    pub const control_status_phase: u8 = 2;

    // USB device to send this to
    device: ?*Device = null,

    // Endpoint descriptor to communicate with on the device. This
    // should come from one of the endpoints in the Device struct. A
    // control transfer can leave this as null
    endpoint_desc: ?*spec.EndpointDescriptor = null,

    // For IN endpoints, this will be filled in up to the length of
    // the buffer. For OUT endpoints, this holds the exact bytes to
    // transmit.
    data: [*]allowzero u8,
    size: TransferBytes = 0,

    // Setup data for a USB control request. Only used when the
    // endpoint descriptor refers to a control endpoint.
    setup_data: SetupPacket,

    // Callback function to be invoked when this transfer completes
    // (or has failed in a terminal way)
    completion: ?Completion = null,

    // The next two fields are the results of this transfer
    // attempt. They are filled in by the driver
    status: CompletionStatus = .incomplete,
    actual_size: TransferBytes = 0,

    // All members below this are internal bookkeeping.
    cur_data_ptr: ?[*]u8 = null,

    complete_split: bool = false,
    short_attempt: bool = false,
    // need_sof: bool = false,
    control_phase: u8 = 0,
    next_data_pid: u2 = 0,

    attempted_size: TransferBytes = 0,
    attempted_bytes_remaining: TransferBytes = 0,
    attempted_packets_remaining: TransferPackets = 0,
    csplit_retries: u16 = 0,
    nak_count: u16 = 0,

    deferrer_thread_sem: ?SID = null,
    deferrer_thread: ?TID = null,

    semaphore: ?SID = semaphore.NO_SEM,

    pub fn create(allocator: std.mem.Allocator, dev: *Device, setup: SetupPacket, buffer: []u8) !*TransferRequest {
        const req = try allocator.create(TransferRequest);
        req.* = .{
            .actual_size = 0,
            .attempted_bytes_remaining = 0,
            .attempted_packets_remaining = 0,
            .attempted_size = 0,
            .control_phase = 0,
            .complete_split = false,
            .csplit_retries = 0,
            .nak_count = 0,
            .device = dev,
            .data = buffer.ptr,
            .size = @truncate(buffer.len),
            .setup_data = setup,
        };
        return req;
    }

    pub fn initControl(dev: *Device, setup_packet: SetupPacket, data_buffer: []u8) TransferRequest {
        return .{
            .device = dev,
            .setup_data = setup_packet,
            .data = data_buffer.ptr,
            .size = @truncate(data_buffer.len),
        };
    }

    pub fn initInterrupt(dev: *Device, data_buffer: []u8) TransferRequest {
        return .{
            .device = dev,
            .endpoint_desc = dev.configuration.endpoints[0][0],
            .setup_data = undefined,
            .data = data_buffer.ptr,
            .size = @truncate(data_buffer.len),
        };
    }

    pub fn deinit(self: *TransferRequest, allocator: std.mem.Allocator) void {
        if (self.deferrer_thread) |tid| {
            schedule.kill(tid);
        }

        if (self.deferrer_thread_sem) |sid| {
            semaphore.free(sid) catch {
                // TODO something
            };
            self.deferrer_thread_sem = null;
        }

        allocator.destroy(self);
    }

    pub fn isControlRequest(self: *const TransferRequest) bool {
        return self.endpoint_desc == null or (self.endpoint_desc.?.isType(TransferType.control));
    }

    pub fn complete(self: *TransferRequest, txn_status: CompletionStatus) void {
        self.status = txn_status;

        if (self.deferrer_thread) |tid| {
            schedule.kill(tid);
        }

        if (self.completion) |c| {
            c(self);
        }
    }
};

pub const TransferType = struct {
    pub const control: u2 = 0b00;
    pub const isochronous: u2 = 0b01;
    pub const bulk: u2 = 0b10;
    pub const interrupt: u2 = 0b11;
};

pub const SetupPacket = extern struct {
    request_type: u8,
    request: u8,
    value: u16,
    index: u16,
    data_size: u16,
};
