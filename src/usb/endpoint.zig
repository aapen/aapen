pub const EndpointDirection = enum(u1) {
    out = 0b0,
    in = 0b1,
};

pub const EndpointNumber = u4;

pub const EndpointType = enum(u2) {
    Control = 0,
    Isochronous = 1,
    Bulk = 2,
    Interrupt = 3,
};
