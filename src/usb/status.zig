pub const Error = error{
    DeviceUnsupported,
    HardwareError,
    InvalidData,
    InvalidParameter,
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
