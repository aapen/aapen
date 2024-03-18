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
    TransferIncomplete,
    TransferStarted,
    TransferTimeout,
    UnsupportedRequest,
};

pub const TransactionStatus = enum {
    ok,
    timeout,
    data_length_mismatch,
    failed,
};
