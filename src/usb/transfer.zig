const request = @import("request.zig");
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;

pub const TransferBytes = u19;
pub const PacketSize = u11;
pub const DEFAULT_MAX_PACKET_SIZE = 8;

/// Describe a single USB transfer to perform. May be any type of
/// transfer, but if it is a control transfer then the setup member
/// must be filled in.
pub const Transfer = struct {
    pub const Completion = *const fn (self: *Transfer) void;

    transfer_type: TransferType,
    setup: SetupPacket,
    data_buffer: []u8,
    actual_size: u16 = 0,
    status: TransferStatus = .incomplete,
    completion: ?Completion = null,

    pub fn complete(self: *Transfer, status: TransferStatus) void {
        self.status = status;

        if (self.completion) |c| {
            c(self);
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

/// Create a SetupPacket. This should normally be wrapped with a more
/// specific function for a device class
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
