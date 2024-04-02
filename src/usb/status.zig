const schedule = @import("../schedule.zig");

pub const Error = error{
    DeviceDetaching,
    DeviceUnconfigured,
    DeviceUnsupported,
    HardwareError,
    InvalidData,
    InvalidParameter,
    InvalidResponse,
    NoDevice,
    NotProcessed,
    OutOfMemory,
    ResetTimeout,
    TooManyDevices,
    TooManyHubs,
    TransferFailed,
    TransferIncomplete,
    TransferStarted,
    TransferTimeout,
    UnsupportedRequest,
} || schedule.Error;

pub const TransactionStatus = enum {
    ok,
    timeout,
    data_length_mismatch,
    failed,
};
