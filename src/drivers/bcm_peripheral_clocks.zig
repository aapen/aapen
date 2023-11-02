const bcm_mailbox = @import("bcm_mailbox.zig");
const BroadcomMailbox = bcm_mailbox.BroadcomMailbox;
const PropertyTag = bcm_mailbox.PropertyTag;

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

pub const DesiredState = enum(u1) {
    off = 0b0,
    on = 0b1,
};

const RateSelector = enum(u32) {
    current = 0x0030002,
    max = 0x00030004,
    min = 0x00030007,
};

pub const ClockResult = enum {
    unknown,
    failed,
    no_such_device,
    clock_on,
    clock_off,
};

const PropertyClock = extern struct {
    tag: PropertyTag,
    clock: u32,
    param2: extern union {
        state: u32,
        rate: u32,
    },

    pub fn initStateQuery(clock: ClockId) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_get_clock_state, 1, 2),
            .clock = @intFromEnum(clock),
            .param2 = .{ .state = 0 },
        };
    }

    pub fn initStateControl(clock: ClockId, desired_state: DesiredState) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_set_clock_state, 2, 2),
            .clock = @intFromEnum(clock),
            .param2 = .{ .state = @intFromEnum(desired_state) },
        };
    }

    pub fn initRateQuery(clock: ClockId, rate_selector: RateSelector) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_get_clock_rate, 1, 2),
            .clock = @intFromEnum(clock),
            .param2 = .{ .rate = @intFromEnum(rate_selector) },
        };
    }
};

const PropertyClockRateControl = extern struct {
    tag: PropertyTag,
    clock: u32,
    rate: u32,
    skip_turbo: u32,

    pub fn initRateControl(clock: ClockId, desired_rate: u32) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_set_clock_rate, 3, 2),
            .clock = @intFromEnum(clock),
            .rate = desired_rate,
            .skip_turbo = 1,
        };
    }
};

pub const PeripheralClockController = struct {
    mailbox: *BroadcomMailbox,

    fn decode(state: u32) ClockResult {
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

    fn clockRate(self: *PeripheralClockController, clock_id: ClockId, selector: RateSelector) !u32 {
        const query = PropertyClock.initRateQuery(clock_id, selector);
        try self.mailbox.getTag(&query);
        return query.param1.rate;
    }

    pub fn clockRateCurrent(self: *PeripheralClockController, clock_id: ClockId) !u32 {
        return self.clockRate(clock_id, .current);
    }

    pub fn clockRateMax(self: *PeripheralClockController, clock_id: ClockId) !u32 {
        return self.clockRate(clock_id, .max);
    }

    pub fn clockRateMin(self: *PeripheralClockController, clock_id: ClockId) !u32 {
        return self.clockRate(clock_id, .min);
    }

    pub fn clockRateSet(self: *PeripheralClockController, clock_id: ClockId, desired_rate: u32) !u32 {
        const control = PropertyClockRateControl.initRateControl(clock_id, desired_rate);
        try self.mailbox.getTag(&control);
        return control.rate;
    }

    fn clockStateSet(self: *PeripheralClockController, clock_id: ClockId, desired_state: DesiredState) !ClockResult {
        const control = PropertyClock.initStateControl(clock_id, desired_state);
        try self.mailbox.getTag(&control);
        return decode(control.param1.state);
    }

    pub fn clockOn(self: *PeripheralClockController, clock_id: ClockId) !ClockResult {
        return self.clockStateSet(clock_id, .on);
    }

    pub fn clockOff(self: *PeripheralClockController, clock_id: ClockId) !ClockResult {
        return self.clockStateSet(clock_id, .off);
    }
};
