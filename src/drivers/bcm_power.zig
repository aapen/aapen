const bcm_mailbox = @import("bcm_mailbox.zig");
const BroadcomMailbox = bcm_mailbox.BroadcomMailbox;
const PropertyTag = bcm_mailbox.PropertyTag;

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

pub const WaitForTransition = enum(u2) {
    do_not_wait = 0b00,
    wait = 0b10,
};

pub const DesiredState = enum(u1) {
    off = 0b0,
    on = 0b1,
};

pub const PowerResult = enum {
    unknown,
    failed,
    no_such_device,
    power_on,
    power_off,
};

const PropertyPower = extern struct {
    tag: PropertyTag,
    device: u32,
    state: u32,

    pub fn initQuery(device: PowerDevice) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_get_power_state, 1, 2),
            .device = @intFromEnum(device),
            .state = 0,
        };
    }

    pub fn initControl(device: PowerDevice, state: DesiredState, wait: WaitForTransition) @This() {
        return .{
            .tag = PropertyTag.init(.rpi_firmware_set_power_state, 2, 2),
            .device = @intFromEnum(device),
            .state = @intFromEnum(state) | @intFromEnum(wait),
        };
    }
};

pub const BroadcomPowerController = struct {
    mailbox: *const BroadcomMailbox,

    pub fn init(mailbox: *BroadcomMailbox) BroadcomPowerController {
        return .{
            .mailbox = mailbox,
        };
    }

    fn decode(state: u32) PowerResult {
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

    pub fn isPowered(self: *const BroadcomPowerController, device: PowerDevice) !PowerResult {
        const query = PropertyPower.initQuery(device);
        try self.mailbox.getTag(&query);
        return decode(query.state);
    }

    fn setState(self: *const BroadcomPowerController, device: PowerDevice, desired_state: DesiredState) !PowerResult {
        var control = PropertyPower.initControl(device, desired_state, .wait);
        try self.mailbox.getTag(&control);
        return decode(control.state);
    }

    pub fn powerOn(self: *const BroadcomPowerController, device: PowerDevice) !PowerResult {
        return self.setState(device, .on);
    }

    pub fn powerOff(self: *const BroadcomPowerController, device: PowerDevice) PowerResult {
        return self.setState(device, .off);
    }
};
