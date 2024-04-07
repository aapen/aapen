const std = @import("std");
const Allocator = std.mem.Allocator;

const time = @import("../arch/aarch64/time.zig");

const GPIO = @import("bcm_gpio.zig");
const Forth = @import("../forty/forth.zig").Forth;

const root = @import("root");
const InterruptController = root.HAL.InterruptController;
const IrqHandler = InterruptController.IrqHandler;
const IrqId = InterruptController.IrqId;

const Self = @This();
pub fn defineModule(forth: *Forth) !void {
    try forth.defineStruct("i2c.status", Status, .{
        .declarations = true,
    });
    try forth.defineNamespace(Self, .{
        .{ "enable", "i2c-enable" },
        .{ "send", "i2c-send" },
        .{ "receive", "i2c-receive" },
    });
}

extern fn spinDelay(cpu_cycles: u32) void;

pub const Status = struct {
    pub const Success: u32 = 0;
    pub const AckError: u32 = 101;
    pub const DataLoss: u32 = 102;
    pub const TimeOut: u32 = 103;
};

// Control register bits.
const Control = struct {
    pub const Enable: u32 = (1 << 15); // I2CEN
    pub const IntRead: u32 = (1 << 10); // INTR
    pub const IntWrite: u32 = (1 << 9); // INTT
    pub const IntDone: u32 = (1 << 8); // INTD
    pub const StartXfer: u32 = (1 << 7); // ST
    pub const Clear: u32 = (1 << 4) | (1 << 5); // CLEAR
    pub const ReadTransfer: u32 = (1 << 0); // READ
};

// Status register bits.
const StatusBits = struct {
    pub const ClockTimeout: u32 = (1 << 9); // CLKT
    pub const AckError: u32 = (1 << 8); // ERR
    pub const FifoFull: u32 = (1 << 7); // RXF
    pub const FifoEmpty: u32 = (1 << 6); // TXE
    pub const FifoNotEmpty: u32 = (1 << 5); // RXD
    pub const FifoCanAccept: u32 = (1 << 4); // TXD
    pub const FifoNeedsReading: u32 = (1 << 3); // TXR
    pub const FifoNeedsWriting: u32 = (1 << 2); // TXW
    pub const Done: u32 = (1 << 1); // Done
    pub const TransferActive: u32 = (1 << 0); // TA
};

const Registers = extern struct {
    control: u32,
    status: u32,
    data_length: u32,
    target_address: u32,
    fifo: u32,
    div: u32,
    delay: u32,
    clock_stretch: u32,
};

const DefaultFrequency: u32 = 100_000;

registers: *volatile Registers,
interrupt_controller: *InterruptController,
gpio: *GPIO,

// Don't need this right now, but probably soon...
irq_handler: IrqHandler = irqHandle,

pub fn init(allocator: Allocator, register_base: u64, gpio: *GPIO, interrupt_controller: *InterruptController) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .registers = @ptrFromInt(register_base),
        .interrupt_controller = interrupt_controller,
        .gpio = gpio,
    };
    return self;
}

pub fn enable(self: *Self, i2c_freq: u64) void {
    self.gpio.enable(2);
    self.gpio.enable(3);

    self.gpio.selectPull(3, GPIO.PullUpDownSelect.Up);
    self.gpio.selectPull(2, GPIO.PullUpDownSelect.Up);
    self.gpio.selectFunction(2, GPIO.FunctionSelect.Alt0);
    self.gpio.selectFunction(3, GPIO.FunctionSelect.Alt0);

    const desired_freq = if (i2c_freq == 0) DefaultFrequency else i2c_freq;
    const divisor: u64 = time.frequency() / desired_freq * 10;
    self.registers.div = @truncate(divisor);
}

pub fn send(self: *Self, target_address: u8, buffer: [*]u8, count: u32) u32 {
    // Start the transfer.

    self.registers.target_address = target_address;
    self.registers.control = Control.Clear;
    self.registers.status = StatusBits.ClockTimeout | StatusBits.AckError | StatusBits.Done;
    self.registers.data_length = count;

    // Prepopulate the FIFO.

    var i: u32 = 0;

    while ((i < count) and (i < 16)) {
        self.registers.fifo = buffer[i];
        i += 1;
    }

    // Start the xfer.

    self.registers.control = Control.Enable | Control.StartXfer;

    while ((self.registers.status & StatusBits.Done) == 0) {
        while ((i < count) and (self.registers.status & StatusBits.FifoCanAccept) != 0) {
            self.registers.fifo = buffer[i];
            i += 1;
        }
        spinDelay(10);
    }

    // Interpret final status.
    const status = self.registers.status;

    self.registers.status = StatusBits.Done;

    if (status & StatusBits.AckError != 0) {
        return Status.AckError;
    } else if (status & StatusBits.ClockTimeout != 0) {
        return Status.TimeOut;
    } else if (i < count) {
        return Status.DataLoss;
    }
    return Status.Success;
}

pub fn receive(self: *Self, target_address: u8, buffer: [*]u8, count: u32) u32 {
    self.registers.target_address = target_address;
    self.registers.control = Control.Clear;
    self.registers.status = StatusBits.ClockTimeout | StatusBits.AckError | StatusBits.Done;
    self.registers.data_length = count;
    self.registers.control = Control.Enable | Control.StartXfer | Control.ReadTransfer;

    // Push the data;

    var i: u64 = 0;

    while ((i < count) and (self.registers.status & StatusBits.Done) == 0) {
        while ((self.registers.status & StatusBits.FifoNotEmpty) != 0) {
            buffer[i] = @truncate(self.registers.fifo);
            i += 1;
        }
    }

    // Interpret final status.
    const status = self.registers.status;
    self.registers.status = StatusBits.Done;

    if (status & StatusBits.AckError != 0) {
        return Status.AckError;
    } else if (status & StatusBits.ClockTimeout != 0) {
        return Status.TimeOut;
    } else if (i < count) {
        return Status.DataLoss;
    }
    return Status.Success;
}

pub fn irqHandle(_: *InterruptController, _: IrqId, private: ?*anyopaque) void {
    var self: *Self = @ptrCast(@alignCast(private));
    _ = self;
}
