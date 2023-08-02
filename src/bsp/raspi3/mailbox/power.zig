const mailbox = @import("../mailbox.zig");
const Message = mailbox.Message;
const Envelope = mailbox.Envelope;

pub const Result = enum {
    unknown,
    failed,
    no_such_device,
    power_on,
    power_off,
};

fn decode(state: u32) Result {
    var no_device = (state & 0x02) != 0;
    var actual_state = (state & 0x01) != 0;

    if (no_device) {
        return .no_such_device;
    } else if (actual_state) {
        return .power_on;
    } else {
        return .power_off;
    }
}

const PowerQuery = struct {
    const Self = @This();
    device: PowerDevice,
    state: Result = .unknown,

    pub fn init(device: PowerDevice) Self {
        return Self{
            .device = device,
        };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, .RPI_FIRMWARE_GET_POWER_STATE, 1, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = @intFromEnum(self.device);
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.device = @enumFromInt(buf[0]);
        self.state = decode(buf[1]);
    }
};

const PowerControl = struct {
    const Self = @This();

    pub const WaitForTransition = enum(u2) {
        do_not_wait = 0b00,
        wait = 0b10,
    };

    pub const DesiredState = enum(u1) {
        off = 0b0,
        on = 0b1,
    };

    device: PowerDevice,
    desired_state: DesiredState = .on,
    wait: WaitForTransition = .wait,
    state: Result = .unknown,

    pub fn init(device: PowerDevice) Self {
        return Self{
            .device = device,
        };
    }
    pub fn message(self: *Self) Message {
        return Message.init(self, .RPI_FIRMWARE_SET_POWER_STATE, 2, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        buf[0] = @intFromEnum(self.device);
        buf[1] = @intFromEnum(self.desired_state) | @intFromEnum(self.wait);
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.device = @enumFromInt(buf[0]);
        self.state = decode(buf[1]);
    }
};

pub const PowerDevice = enum(u32) {
    sdhci = 0,
    uart0 = 1,
    uart1 = 2,
    usb_hcd = 3,
    i2c0 = 4,
    i2c1 = 5,
    i2c2 = 6,
    spi = 7,
    ccp2tx = 8,
};

pub fn isPowered(device: PowerDevice) !Result {
    var power_query = PowerQuery.init(device);
    var messages = [_]Message{power_query.message()};
    var env = Envelope.init(&messages);
    _ = env.call() catch 0;

    return power_query.state;
}

pub fn powerOn(device: PowerDevice) !Result {
    var power_control = PowerControl.init(device);
    var messages = [_]Message{power_control.message()};
    var env = Envelope.init(&messages);
    _ = env.call() catch 0;

    return power_control.state;
}
