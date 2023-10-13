pub const USB = struct {
    powerOn: *const fn (usb: *USB) void,
    powerOff: *const fn (usb: *USB) void,
};
