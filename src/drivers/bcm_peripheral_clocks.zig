const std = @import("std");
const root = @import("root");
const Mailbox = root.HAL.Mailbox;
const PropertyTag = root.HAL.Mailbox.PropertyTag;

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

    pub fn initStateQuery(clock: ClockId) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_get_clock_state, 1, 2),
            .clock = @intFromEnum(clock),
            .param2 = 0,
        };
    }

    pub fn initStateControl(clock: ClockId, desired_state: DesiredState) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_set_clock_state, 2, 2),
            .clock = @intFromEnum(clock),
            .param2 = @intFromEnum(desired_state),
        };
    }

    pub fn initRateQuery(clock: ClockId, rate_selector: RateSelector) @This() {
        const tag = @intFromEnum(rate_selector);

        return .{
            .tag = PropertyTag.init(@enumFromInt(tag), 1, 2),
            .clock = @intFromEnum(clock),
            .param2 = 0,
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
    pub const VTable = struct {
        clockRateGet: *const fn (controller: u64, clock_id: u64) u64,
        clockStateGet: *const fn (controller: u64, clock_id: u64) u64,
    };

    mailbox: *Mailbox,
    vtable: VTable = .{
        .clockRateGet = clockRateGetShim,
        .clockStateGet = clockStateGetShim,
    },

    fn clockRateGetShim(controller: u64, clock_id: u64) u64 {
        const self: *PeripheralClockController = @ptrFromInt(controller);

        if (std.meta.intToEnum(ClockId, clock_id)) |clk| {
            if (self.clockRateCurrent(clk)) |rate| {
                return rate;
            } else |err| {
                std.log.warn("error querying clock rate: {any}", .{err});
                return 0;
            }
        } else |_| {
            std.log.warn("invalid clock id", .{});
            return 0;
        }
    }

    fn clockStateGetShim(controller: u64, clock_id: u64) u64 {
        const self: *PeripheralClockController = @ptrFromInt(controller);

        if (std.meta.intToEnum(ClockId, clock_id)) |clk| {
            if (self.clockState(clk)) |state| {
                return @intFromEnum(state);
            } else |err| {
                _ = err;
                return 0;
            }
        } else |_| {
            std.log.warn("invalid clock id", .{});
            return 0;
        }
    }

    pub fn init(mailbox: *Mailbox) PeripheralClockController {
        return .{
            .mailbox = mailbox,
        };
    }

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
        var query = PropertyClock.initRateQuery(clock_id, selector);
        try self.mailbox.getTag(&query);
        return query.param2;
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

    fn clockState(self: *PeripheralClockController, clock_id: ClockId) !ClockResult {
        const query = PropertyClock.initStateQuery(clock_id);
        try self.mailbox.getTag(&query);
        return decode(query.clock);
    }

    pub fn clockOn(self: *PeripheralClockController, clock_id: ClockId) !ClockResult {
        return self.clockStateSet(clock_id, .on);
    }

    pub fn clockOff(self: *PeripheralClockController, clock_id: ClockId) !ClockResult {
        return self.clockStateSet(clock_id, .off);
    }
};
