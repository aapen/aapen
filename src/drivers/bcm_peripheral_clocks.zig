const bcm_mailbox = @import("bcm_mailbox.zig");
const BroadcomMailbox = bcm_mailbox.BroadcomMailbox;
const Message = BroadcomMailbox.Message;
const Envelope = BroadcomMailbox.Envelope;

pub const ClockId = enum(u32) {
    reserved = 0,
    emmc = 1,
    uart = 2,
    arm = 3,
    core = 4,
    v3d = 5,
    h264 = 6,
    isp = 7,
    sdram = 8,
    pixel = 9,
    pwm = 10,
};

pub const PeripheralClockController = struct {
    mailbox: *BroadcomMailbox = undefined,

    pub fn init(self: *PeripheralClockController, mailbox: *BroadcomMailbox) void {
        self.mailbox = mailbox;
    }

    pub const Result = enum {
        unknown,
        failed,
        no_such_device,
        clock_on,
        clock_off,
    };

    fn decode(state: u32) Result {
        var no_device = (state & 0x02) != 0;
        var actual_state = (state & 0x01) != 0;

        if (no_device) {
            return .no_such_device;
        } else if (actual_state) {
            return .clock_on;
        } else {
            return .clock_off;
        }
    }

    const StateQueryMessage = struct {
        const Self = @This();
        clock_id: ClockId = .reserved,
        state: Result = .unknown,

        pub fn init(clock_id: ClockId) Self {
            return Self{
                .clock_id = clock_id,
            };
        }

        pub fn message(self: *Self) Message {
            return Message.init(self, .rpi_firmware_get_clock_state, 1, 2);
        }

        pub fn fill(self: *Self, buf: []u32) void {
            buf[0] = @intFromEnum(self.clock_id);
        }

        pub fn unfill(self: *Self, buf: []u32) void {
            self.clock_id = @enumFromInt(buf[0]);
            self.state = decode(buf[1]);
        }
    };

    const StateControlMessage = struct {
        const Self = @This();

        pub const DesiredState = enum(u1) {
            off = 0b0,
            on = 0b1,
        };

        clock_id: ClockId,
        desired_state: DesiredState = .on,
        state: Result = .unknown,

        pub fn init(clock_id: ClockId, desired_state: DesiredState) Self {
            return Self{
                .clock_id = clock_id,
                .desired_state = desired_state,
            };
        }

        pub fn message(self: *Self) Message {
            return Message.init(self, .rpi_firmware_set_clock_state, 2, 2);
        }

        pub fn fill(self: *Self, buf: []u32) void {
            buf[0] = @intFromEnum(self.clock_id);
            buf[1] = @intFromEnum(self.desired_state);
        }

        pub fn unfill(self: *Self, buf: []u32) void {
            self.clock_id = @enumFromInt(buf[0]);
            self.state = decode(buf[1]);
        }
    };

    const RateQueryMessage = struct {
        const RateSelector = enum(u32) {
            current = 0x0030002,
            max = 0x00030004,
            min = 0x00030007,
        };

        const Self = @This();

        clock_id: ClockId = .reserved,
        selector: RateSelector = undefined,
        rate: u32 = undefined,

        pub fn init(clock_id: ClockId, selector: RateSelector) Self {
            return Self{
                .clock_id = clock_id,
                .selector = selector,
            };
        }

        pub fn message(self: *Self) Message {
            return Message.init(self, @enumFromInt(@intFromEnum(self.selector)), 1, 2);
        }

        pub fn fill(self: *Self, buf: []u32) void {
            buf[0] = @intFromEnum(self.clock_id);
        }

        pub fn unfill(self: *Self, buf: []u32) void {
            self.clock_id = @enumFromInt(buf[0]);
            self.rate = buf[1];
        }
    };

    const RateControlMessage = struct {
        const Self = @This();

        clock_id: ClockId,
        desired_rate: u32 = undefined,
        rate: u32 = undefined,

        pub fn init(clock_id: ClockId, desired_rate: u32) Self {
            return Self{
                .clock_id = clock_id,
                .desired_rate = desired_rate,
            };
        }

        pub fn message(self: *Self) Message {
            return Message.init(self, .rpi_firmware_set_clock_rate, 3, 2);
        }

        pub fn fill(self: *Self, buf: []u32) void {
            buf[0] = @intFromEnum(self.clock_id);
            buf[1] = self.desired_rate;
            buf[2] = 1; // skip setting turbo ??
        }

        pub fn unfill(self: *Self, buf: []u32) void {
            self.clock_id = @enumFromInt(buf[0]);
            self.rate = buf[1];
        }
    };

    fn clockRate(self: *PeripheralClockController, clock_id: ClockId, selector: RateQueryMessage.RateSelector) u32 {
        var query = RateQueryMessage.init(clock_id, selector);
        var messages = [_]Message{query.message()};
        var env = Envelope.init(self.mailbox, &messages);
        _ = env.call() catch 0;
        return query.rate;
    }

    pub fn clockRateCurrent(self: *PeripheralClockController, clock_id: ClockId) u32 {
        return self.clockRate(clock_id, .current);
    }

    pub fn clockRateMax(self: *PeripheralClockController, clock_id: ClockId) u32 {
        return self.clockRate(clock_id, .max);
    }

    pub fn clockRateMin(self: *PeripheralClockController, clock_id: ClockId) u32 {
        return self.clockRate(clock_id, .min);
    }

    pub fn clockRateSet(self: *PeripheralClockController, clock_id: ClockId, desired_rate: u32) void {
        var control = RateControlMessage.init(clock_id, desired_rate);
        var messages = [_]Message{control.message()};
        var env = Envelope.init(self.mailbox, &messages);
        _ = env.call() catch 0;
        return control.rate;
    }

    fn clockStateSet(self: *PeripheralClockController, clock_id: ClockId, desired_state: StateControlMessage.DesiredState) Result {
        var control = StateControlMessage.init(clock_id, desired_state);
        var messages = [_]Message{control.message()};
        var env = Envelope.init(self.mailbox, &messages);
        _ = env.call() catch 0;
        return control.state;
    }

    pub fn clockOn(self: *PeripheralClockController, clock_id: ClockId) Result {
        return self.clockStateSet(clock_id, .on);
    }

    pub fn clockOff(self: *PeripheralClockController, clock_id: ClockId) Result {
        return self.clockStateSet(clock_id, .off);
    }
};
