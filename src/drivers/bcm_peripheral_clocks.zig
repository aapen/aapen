const std = @import("std");

const Forth = @import("../forty/forth.zig");

const root = @import("root");
const Mailbox = root.HAL.Mailbox;
const PropertyTag = root.HAL.Mailbox.PropertyTag;

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(PeripheralClockController, .{
        .{ "clockRateCurrent", "clock-rate" },
        .{ "clockRateMax", "clock-rate-max" },
        .{ "clockRateMin", "clock-rate-min" },
        .{ "clockRateSet", "clock-set-rate" },
        .{ "clockStateSet", "clock-set-state" },
        .{ "clockState", "clock-state" },
        .{ "clockOn", "clock-on" },
        .{ "clockOff", "clock-off" },
    });
}

pub const CLOCK_RESERVED: u32 = 0;
pub const CLOCK_EMMC: u32 = 1;
pub const CLOCK_UART: u32 = 2;
pub const CLOCK_ARM: u32 = 3;
pub const CLOCK_CORE: u32 = 4;
pub const CLOCK_V3D: u32 = 5;
pub const CLOCK_H264: u32 = 6;
pub const CLOCK_ISP: u32 = 7;
pub const CLOCK_SDRAM: u32 = 8;
pub const CLOCK_PIXEL: u32 = 9;
pub const CLOCK_PWM: u32 = 10;

pub const STATE_OFF: u32 = 0;
pub const STATE_ON: u32 = 1;

pub const ClockResult = enum(u64) {
    unknown = 0,
    failed = 1,
    no_such_device = 2,
    clock_on = 3,
    clock_off = 4,
};

const PropertyClock = extern struct {
    tag: PropertyTag,
    clock: u32,
    param2: u32,

    pub fn initStateQuery(clock: u32) @This() {
        return .{
            .tag = PropertyTag.init(Mailbox.RPI_FIRMWARE_GET_CLOCK_STATE, 1, 2),
            .clock = clock,
            .param2 = 0,
        };
    }

    pub fn initStateControl(clock: u32, desired_state: u32) @This() {
        return .{
            .tag = PropertyTag.init(Mailbox.RPI_FIRMWARE_SET_CLOCK_STATE, 2, 2),
            .clock = clock,
            .param2 = desired_state,
        };
    }

    pub fn initRateQuery(clock: u32, rate_selector: u32) @This() {
        return .{
            .tag = PropertyTag.init(rate_selector, 1, 2),
            .clock = clock,
            .param2 = 0,
        };
    }
};

const PropertyClockRateControl = extern struct {
    tag: PropertyTag,
    clock: u32,
    rate: u32,
    skip_turbo: u32,

    pub fn initRateControl(clock: u32, desired_rate: u32) @This() {
        return .{
            .tag = PropertyTag.init(Mailbox.RPI_FIRMWARE_SET_CLOCK_RATE, 3, 2),
            .clock = clock,
            .rate = desired_rate,
            .skip_turbo = 1,
        };
    }
};

pub const PeripheralClockController = struct {
    mailbox: *Mailbox,

    pub fn init(mailbox: *Mailbox) PeripheralClockController {
        return .{
            .mailbox = mailbox,
        };
    }

    fn decode(state: u32) ClockResult {
        const no_device = (state & 0x02) != 0;
        const actual_state = (state & 0x01) != 0;

        if (no_device) {
            return .no_such_device;
        } else if (actual_state) {
            return .clock_on;
        } else {
            return .clock_off;
        }
    }

    fn clockRate(self: *PeripheralClockController, clock_id: u32, selector: u32) !u32 {
        var query = PropertyClock.initRateQuery(clock_id, selector);
        try self.mailbox.getTag(&query);
        return query.param2;
    }

    pub fn clockRateCurrent(self: *PeripheralClockController, clock_id: u32) !u32 {
        return self.clockRate(clock_id, Mailbox.RPI_FIRMWARE_GET_CLOCK_RATE);
    }

    pub fn clockRateMax(self: *PeripheralClockController, clock_id: u32) !u32 {
        return self.clockRate(clock_id, Mailbox.RPI_FIRMWARE_GET_MAX_CLOCK_RATE);
    }

    pub fn clockRateMin(self: *PeripheralClockController, clock_id: u32) !u32 {
        return self.clockRate(clock_id, Mailbox.RPI_FIRMWARE_GET_MIN_CLOCK_RATE);
    }

    pub fn clockRateSet(self: *PeripheralClockController, clock_id: u32, desired_rate: u32) !u32 {
        const control = PropertyClockRateControl.initRateControl(clock_id, desired_rate);
        try self.mailbox.getTag(&control);
        return control.rate;
    }

    pub fn clockStateSet(self: *PeripheralClockController, clock_id: u32, desired_state: u32) !ClockResult {
        const control = PropertyClock.initStateControl(clock_id, desired_state);
        try self.mailbox.getTag(&control);
        return decode(control.param2);
    }

    pub fn clockState(self: *PeripheralClockController, clock_id: u32) !ClockResult {
        const query = PropertyClock.initStateQuery(clock_id);
        try self.mailbox.getTag(&query);
        return decode(query.clock);
    }

    pub fn clockOn(self: *PeripheralClockController, clock_id: u32) !ClockResult {
        return self.clockStateSet(clock_id, STATE_ON);
    }

    pub fn clockOff(self: *PeripheralClockController, clock_id: u32) !ClockResult {
        return self.clockStateSet(clock_id, STATE_OFF);
    }
};
