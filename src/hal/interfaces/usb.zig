pub const Error = error{
    OutOfMemory,
    HostInitializationError,
    HubInitializationError,
    DeviceInitializationError,
};

pub const USB = struct {
    powerOn: *const fn (usb: *USB) void,
    powerOff: *const fn (usb: *USB) void,
    hostControllerInitialize: *const fn (usb: *USB) Error!void,
};
