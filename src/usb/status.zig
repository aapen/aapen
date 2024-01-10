pub const Error = error{
    TooManyDevices,
    DeviceUnsupported,
    HardwareError,
    InvalidData,
    InvalidParameter,
    InvalidResponse,
    NotProcessed,
    OutOfMemory,
    Timeout,
    UnsupportedRequest,
};

pub const TransactionStatus = enum {
    ok,
    timeout,
    data_length_mismatch,
    failed,
};
