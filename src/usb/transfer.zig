const std = @import("std");
const log = std.log.scoped(.usb);

const request = @import("request.zig");
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

    pub const State = enum {
        token,
        data,
        handshake,
        complete,
    };

    state: State = undefined,
    transfer_type: TransferType,
    setup: SetupPacket, // only used when transfer_type == .control,
    data_buffer: []u8,
    actual_size: u16 = 0,
    status: TransferStatus = .incomplete,
    completion: ?Completion = null,

    pub fn initControl(setup_packet: *const SetupPacket, data_buffer: []u8) Transfer {
        return .{
            .state = .token,
            .transfer_type = .control,
            .setup = setup_packet.*,
            .data_buffer = data_buffer,
        };
    }

    pub fn complete(self: *Transfer, txn_status: TransferStatus) void {
        self.state = .complete;
        self.status = txn_status;

        if (self.completion) |c| {
            c(self);
        }
    }

    pub fn transferCompleteTransaction(self: *Transfer, txn_status: TransactionStatus) void {
        // The Transfer's state machine goes in here.
        switch (self.transfer_type) {
            .control => self.transferCompleteControlTransaction(txn_status),
            else => {
                log.warn("transferCompleteTransaction: unsupported transfer type {s}", .{@tagName(self.transfer_type)});
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
            },
            .data => switch (txn_status) {
                .ok => self.state = .handshake,
            },
            .handshake => switch (txn_status) {
                .ok => self.complete(.ok),
            },
            .complete => {
                log.warn("transferCompleteControlTransaction: was called after transfer had already completed", .{});
            },
        }
    }
};

pub const PID = enum(u8) {
    Setup,
    Data0,
    Data1,
};

pub const PID2 = enum(u4) {
    token_out = 0b0001,
    token_in = 0b1001,
    token_sof = 0b0101,
    token_setup = 0b1101,
    data_data0 = 0b0011,
    data_data1 = 0b1011,
    data_data2 = 0b0111,
    data_mdata = 0b1111,
    handshake_ack = 0b0010,
    handshake_nak = 0b1010,
    handshake_stall = 0b1110,
    handshake_nyet = 0b0110,
    special_preamble_or_err = 0b1100,
    special_split = 0b1000,
    special_ping = 0b0100,
};

pub const TransferType = enum(u2) {
    control = 0b00,
    isochronous = 0b01,
    bulk = 0b10,
    interrupt = 0b11,
};

pub const TransferStatus = enum {
    incomplete,
    ok,
    unsupported_request,
    timeout,
};

pub const SetupPacket = extern struct {
    request_type: request.RequestType,
    request: u8,
    value: u16,
    index: u16,
    data_size: u16,
};

pub const TransactionStage = enum {
    token,
    data,
    status,
};

/// Create a SetupPacket for a control transfer. This should normally be wrapped with a more
/// specific function for a device, interface, or endpoint
pub fn setup(
    recip: RequestTypeRecipient,
    rtt: RequestTypeType,
    dir: RequestTypeDirection,
    rq: u8,
    value: u16,
    index: u16,
    data_size: u16,
) SetupPacket {
    return .{
        .request_type = .{
            .recipient = recip,
            .type = rtt,
            .transfer_direction = dir,
        },
        .request = rq,
        .value = value,
        .index = index,
        .data_size = data_size,
    };
}

// ----------------------------------------------------------------------
// Testing
// ----------------------------------------------------------------------

const expectEqual = std.testing.expectEqual;

test "control transfer starts with the .token phase" {
    std.debug.print("\n", .{});

    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = setup(.device, .standard, .device_to_host, 0x06, 0, 0, buffer_size);
    const xfer = Transfer.initControl(&pkt, &buffer);

    try expectEqual(Transfer.State.token, xfer.state);
}

test "control transfer with data expected has three phases" {
    std.debug.print("\n", .{});

    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = setup(.device, .standard, .device_to_host, 0x06, 0, 0, buffer_size);
    var xfer = Transfer.initControl(&pkt, &buffer);

    try expectEqual(Transfer.State.token, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    try expectEqual(Transfer.State.data, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    try expectEqual(Transfer.State.handshake, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    try expectEqual(Transfer.State.complete, xfer.state);
    try expectEqual(TransferStatus.ok, xfer.status);
}

test "control transfer with no data expected has only two phases" {
    std.debug.print("\n", .{});

    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = setup(.device, .standard, .host_to_device, 0x05, 1, 0, buffer_size);
    var xfer = Transfer.initControl(&pkt, &buffer);

    try expectEqual(Transfer.State.token, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    try expectEqual(Transfer.State.handshake, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    try expectEqual(Transfer.State.complete, xfer.state);
    try expectEqual(TransferStatus.ok, xfer.status);
}
