const request = @import("request.zig");
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;

pub const TransferType = enum(u2) {
    control = 0b00,
    isochronous = 0b01,
    bulk = 0b10,
    interrupt = 0b11,
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
