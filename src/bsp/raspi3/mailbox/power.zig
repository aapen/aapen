const mailbox = @import("../mailbox.zig");
const Message = mailbox.Message;
const Envelope = mailbox.Envelope;

pub const PowerDomain = enum(u32) {
    I2C0 = 0,
    I2C1 = 1,
    I2C2 = 2,
    VIDEO_SCALER = 3,
    VPU1 = 4,
    HDMI = 5,
    USB = 6,
    VEC = 7,
    JPEG = 8,
    H264 = 9,
    V3D = 10,
    ISP = 11,
    UNICAM0 = 12,
    UNICAM1 = 13,
    CCP2RX = 14,
    CSI2 = 15,
    CPI = 16,
    DSI0 = 17,
    DSI1 = 18,
    TRANSPOSER = 19,
    CCP2TX = 20,
    CDP = 21,
    ARM = 22,
};

const PowerMessage = struct {
    const Self = @This();
    domain: PowerDomain,
    state: u32 = 0,

    pub fn init(domain: PowerDomain) Self {
        return Self{
            .domain = domain,
        };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, .RPI_FIRMWARE_GET_DOMAIN_STATE, 1, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = @intFromEnum(self.domain);
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.domain = @enumFromInt(buf[0]);
        self.rate = buf[1];
    }
};

pub fn get_power_status(domain: PowerDomain) !struct { bool, u32 } {
    var powermsg = PowerMessage.init(domain);
    var messages = [_]Message{powermsg.message()};
    var env = Envelope.init(&messages);
    _ = try env.call();

    return .{ true, powermsg.state };
}
