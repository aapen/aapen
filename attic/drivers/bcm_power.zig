const root = @import("root");
const Mailbox = root.HAL.Mailbox;
const PropertyTag = root.HAL.Mailbox.PropertyTag;

const Forth = @import("../forty/forth.zig");

const Self = @This();

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "systemPowerQuery", "?power", "check power state of device" },
        .{ "systemPowerControl", "power", "set device to power state" },
    });
}

// global wrappers that uses the initialized device to call the
// instance function below (which leads to the question, "why do we
// make these instance methods at all?")
pub fn systemPowerQuery(device: u32) !PowerResult {
    return root.hal.power_controller.isPowered(device);
}

pub fn systemPowerControl(device: u32, desired_state: u32) !PowerResult {
    return root.hal.power_controller.setState(device, desired_state);
}

pub const POWER_DEVICE_SDHCI: u32 = 0;
pub const POWER_DEVICE_UART0: u32 = 1;
pub const POWER_DEVICE_UART1: u32 = 2;
pub const POWER_DEVICE_USB_HCD: u32 = 3;
pub const POWER_DEVICE_I2C0: u32 = 4;
pub const POWER_DEVICE_I2C1: u32 = 5;
pub const POWER_DEVICE_I2C2: u32 = 6;
pub const POWER_DEVICE_SPI: u32 = 7;
pub const POWER_DEVICE_CCP2TX: u32 = 8;

pub const STATE_OFF: u32 = 0b0;
pub const STATE_ON: u32 = 0b1;

pub const DO_NOT_WAIT_FOR_TRANSITION: u32 = 0b00;
pub const WAIT_FOR_TRANSITION: u32 = 0b10;

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

    pub fn initQuery(device: u32) @This() {
        return .{
            .tag = PropertyTag.init(Mailbox.RPI_FIRMWARE_GET_POWER_STATE, 1, 2),
            .device = device,
            .state = 0,
        };
    }

    pub fn initControl(device: u32, state: u32, wait: bool) @This() {
        return .{
            .tag = PropertyTag.init(Mailbox.RPI_FIRMWARE_SET_POWER_STATE, 2, 2),
            .device = device,
            .state = state | (if (wait) WAIT_FOR_TRANSITION else DO_NOT_WAIT_FOR_TRANSITION),
        };
    }
};

mailbox: *Mailbox,

pub fn init(mailbox: *Mailbox) Self {
    return .{
        .mailbox = mailbox,
    };
}

fn decode(state: u32) PowerResult {
    const no_device = (state & 0x02) != 0;
    const actual_state = (state & 0x01) != 0;

    if (no_device) {
        return .no_such_device;
    } else if (actual_state) {
        return .power_on;
    } else {
        return .power_off;
    }
}

pub fn isPowered(self: *Self, device: u32) !PowerResult {
    const query = PropertyPower.initQuery(device);
    try self.mailbox.getTag(&query);
    return decode(query.state);
}

pub fn setState(self: *Self, device: u32, desired_state: u32) !PowerResult {
    var control = PropertyPower.initControl(device, desired_state, true);
    try self.mailbox.getTag(&control);
    return decode(control.state);
}

pub fn powerOn(self: *Self, device: u32) !PowerResult {
    return self.setState(device, STATE_ON);
}

pub fn powerOff(self: *Self, device: u32) PowerResult {
    return self.setState(device, STATE_OFF);
}
