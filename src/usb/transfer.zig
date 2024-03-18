const std = @import("std");
const log = std.log.scoped(.usb);

const descriptor = @import("descriptor.zig");

const device = @import("device.zig");
const DEFAULT_ADDRESS = device.DEFAULT_ADDRESS;
const DeviceAddress = device.DeviceAddress;
const Device = device.Device;
const UsbSpeed = device.UsbSpeed;
const StandardDeviceRequests = device.StandardDeviceRequests;

const endpoint = @import("endpoint.zig");
const EndpointDirection = endpoint.EndpointDirection;
const EndpointNumber = endpoint.EndpointNumber;

const request = @import("request.zig");
const RequestType = request.RequestType;
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;

const status = @import("status.zig");
const TransactionStatus = status.TransactionStatus;

pub const TransferBytes = u19;
pub const PacketSize = u11;
pub const DEFAULT_MAX_PACKET_SIZE = 8;

/// Describe a single USB transfer to perform. May be any type of
/// transfer, but if it is a control transfer then the setup member
/// must be filled in.
///
/// A Transfer usually consists of multiple stages, each called a
/// Transaction. On completion of a Transaction, the transfer may
/// continue with the next stage or, if the transaction had a problem,
/// may indicate a retry or may report failure.
pub const Transfer = struct {
    pub const Completion = *const fn (self: *Transfer) void;

    pub const CompletionStatus = enum {
        incomplete,
        ok,
        unsupported_request,
        timeout,
        protocol_error,
    };

    pub const State = enum {
        token,
        data,
        handshake,
        complete,
    };

    device: ?*Device = undefined,
    device_address: DeviceAddress = DEFAULT_ADDRESS,
    device_speed: UsbSpeed = .Full,
    endpoint_number: EndpointNumber = 0,
    endpoint_type: u2 = TransferType.control,
    direction: u1 = EndpointDirection.in,
    max_packet_size: PacketSize = DEFAULT_MAX_PACKET_SIZE,
    setup: SetupPacket, // only used when transfer_type == .control,
    data_buffer: []u8,
    actual_size: TransferBytes = 0,
    status: CompletionStatus = .incomplete,
    completion: ?Completion = null,
    state: State = undefined,
    timeout: usize = 100,

    pub fn initControl(setup_packet: SetupPacket, data_buffer: []u8) Transfer {
        return .{
            .device = null,
            .endpoint_number = 0,
            .endpoint_type = TransferType.control,
            .state = .token,
            .setup = setup_packet,
            .data_buffer = data_buffer,
        };
    }

    pub fn initInterrupt(data_buffer: []u8) Transfer {
        return .{
            .device = null,
            .endpoint_number = 0,
            .endpoint_type = TransferType.interrupt,
            // only the data size on the setup packet matters.
            .setup = SetupPacket.init(RequestTypeRecipient.device, RequestTypeType.standard, RequestTypeDirection.device_to_host, 0, 0, 0, @truncate(data_buffer.len)),
            .data_buffer = data_buffer,
        };
    }

    pub fn addressTo(self: *Transfer, dev: *Device) void {
        self.device = dev;
        self.device_address = dev.address;
    }

    pub fn complete(self: *Transfer, txn_status: CompletionStatus) void {
        self.state = .complete;
        self.status = txn_status;

        if (self.completion) |c| {
            c(self);
        }
    }

    pub fn transferCompleteTransaction(self: *Transfer, txn_status: TransactionStatus) void {
        // The Transfer's state machine goes in here.
        switch (self.endpoint_type) {
            TransferType.control => self.transferCompleteControlTransaction(txn_status),
            TransferType.interrupt => self.complete(.ok),
            else => {
                log.warn("transferCompleteTransaction: unsupported transfer type 0x{x}", .{self.endpoint_type});
            },
        }
    }

    fn transferCompleteControlTransaction(self: *Transfer, txn_status: TransactionStatus) void {
        switch (self.state) {
            .token => switch (txn_status) {
                .ok => {
                    if (self.setup.data_size > 0) {
                        self.state = .data;
                    } else {
                        self.state = .handshake;
                    }
                },
                .timeout => {
                    // TODO do we retry? do we halt? for now, just
                    // report failure
                    self.complete(.timeout);
                },
                inline else => self.complete(.protocol_error),
            },
            .data => switch (txn_status) {
                .ok => self.state = .handshake,
                .timeout => self.complete(.timeout),
                inline else => self.complete(.protocol_error),
            },
            .handshake => switch (txn_status) {
                .ok => self.complete(.ok),
                .timeout => self.complete(.timeout),
                inline else => self.complete(.protocol_error),
            },
            .complete => {
                log.warn("transferCompleteControlTransaction: was called after transfer had already completed", .{});
            },
        }
    }

    pub fn getTransactionPid(self: *Transfer) u4 {
        // this probably needs to be extended to account for the
        // transfer type
        return switch (self.state) {
            .token => PID2.token_setup,
            .data => PID2.data_data1,
            .handshake => PID2.handshake_ack,
            .complete => PID2.handshake_nak,
        };
    }
};

pub const PID2 = struct {
    pub const token_out: u4 = 0b0001;
    pub const token_in: u4 = 0b1001;
    pub const token_sof: u4 = 0b0101;
    pub const token_setup: u4 = 0b1101;
    pub const data_data0: u4 = 0b0011;
    pub const data_data1: u4 = 0b1011;
    pub const data_data2: u4 = 0b0111;
    pub const data_mdata: u4 = 0b1111;
    pub const handshake_ack: u4 = 0b0010;
    pub const handshake_nak: u4 = 0b1010;
    pub const handshake_stall: u4 = 0b1110;
    pub const handshake_nyet: u4 = 0b0110;
    pub const special_preamble_or_err: u4 = 0b1100;
    pub const special_split: u4 = 0b1000;
    pub const special_ping: u4 = 0b0100;
};

pub const TransferType = struct {
    pub const control: u2 = 0b00;
    pub const isochronous: u2 = 0b01;
    pub const bulk: u2 = 0b10;
    pub const interrupt: u2 = 0b11;
};

pub const SetupPacket = extern struct {
    request_type: RequestType,
    request: u8,
    value: u16,
    index: u16,
    data_size: u16,

    pub fn init(
        recip: u5,
        rtt: u2,
        dir: u1,
        rq: u8,
        value: u16,
        index: u16,
        data_size: u16,
    ) SetupPacket {
        return .{
            .request_type = request.RT(recip, rtt, dir),
            .request = rq,
            .value = value,
            .index = index,
            .data_size = data_size,
        };
    }
};
