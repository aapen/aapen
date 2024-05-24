const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const HAL = root.HAL;

const Forth = @import("../forty/forth.zig").Forth;

const debug = @import("../debug.zig");

const arch = @import("../architecture.zig");
const exceptions = arch.cpu.exceptions;
const ExceptionContext = exceptions.ExceptionContext;

const synchronize = @import("../synchronize.zig");
const TicketLock = synchronize.TicketLock;

const Self = @This();

pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(@This(), .{
        .{ "irqEnabled1", "irq-enabled-1" },
        .{ "irqEnabled2", "irq-enabled-2" },
        .{ "irqEnabledBasic", "irq-enabled-basic" },
        .{ "irqFlags", "irq-flags" },
    });
}

pub fn irqEnabled1() u64 {
    return root.hal.interrupt_controller.registers.enable_irqs_1;
}

pub fn irqEnabled2() u64 {
    return root.hal.interrupt_controller.registers.enable_irqs_2;
}

pub fn irqEnabledBasic() u64 {
    return root.hal.interrupt_controller.registers.enable_basic_irqs;
}

pub fn irqFlags() u64 {
    return arch.cpu.irqFlagsRead();
}

// ----------------------------------------------------------------------
// External IRQ Identifiers
// ----------------------------------------------------------------------
pub const max_irq_id = 96;

pub const IrqId = u7;

pub const Irq = struct {
    const extended_1: IrqId = 32;

    pub const ARM_TIMER: IrqId = 0;

    pub const TIMER_0: IrqId = Irq.fromGpuIrq(0);
    pub const TIMER_1: IrqId = Irq.fromGpuIrq(1);
    pub const TIMER_2: IrqId = Irq.fromGpuIrq(2);
    pub const TIMER_3: IrqId = Irq.fromGpuIrq(3);
    pub const GPU_7: IrqId = Irq.fromGpuIrq(7);
    pub const USB_HCI: IrqId = Irq.fromGpuIrq(9);
    pub const GPU_10: IrqId = Irq.fromGpuIrq(10);
    pub const GPU_18: IrqId = Irq.fromGpuIrq(18);
    pub const GPU_19: IrqId = Irq.fromGpuIrq(19);
    pub const GPIO_0: IrqId = Irq.fromGpuIrq(49);
    pub const GPIO_1: IrqId = Irq.fromGpuIrq(50);
    pub const GPIO_2: IrqId = Irq.fromGpuIrq(51);
    pub const GPIO_3: IrqId = Irq.fromGpuIrq(52);
    pub const I2C: IrqId = Irq.fromGpuIrq(53);
    pub const SPI: IrqId = Irq.fromGpuIrq(54);
    pub const PCM: IrqId = Irq.fromGpuIrq(55);
    pub const GPU_56: IrqId = Irq.fromGpuIrq(56);
    pub const UART: IrqId = Irq.fromGpuIrq(57);
    pub const GPU_62: IrqId = Irq.fromGpuIrq(62);

    pub fn fromGpuIrq(gpu_irq_id: u32) IrqId {
        return extended_1 + @as(IrqId, @truncate(gpu_irq_id));
    }
};

const IrqRouting = struct {
    enable_mask_basic: u32,
    enable_mask_extended: u64,
    handler: ?*IrqHandler,
    private: ?*anyopaque,

    fn from(irq_id: IrqId) IrqRouting {
        const en = if (irq_id < Irq.extended_1)
            @as(u32, 1) << @truncate(irq_id)
        else
            0;

        const enx = if (irq_id >= Irq.extended_1)
            @as(u64, 1) << @truncate(irq_id - Irq.extended_1)
        else
            0;

        return .{
            .enable_mask_basic = en,
            .enable_mask_extended = enx,
            .handler = null,
            .private = null,
        };
    }

    fn invoke(this: *const IrqRouting, controller: *Self, id: IrqId) void {
        if (this.handler) |h| {
            h.*(controller, id, this.private);
        }
    }
};

pub const IrqHandler = *const fn (*Self, IrqId, ?*anyopaque) void;

// ----------------------------------------------------------------------
// Interrupt controller
// ----------------------------------------------------------------------

const Registers = extern struct {
    irq_pending: [3]u32,
    fiq_control: u32,
    enable_irqs_1: u32,
    enable_irqs_2: u32,
    enable_basic_irqs: u32,
    disable_irqs_1: u32,
    disable_irqs_2: u32,
    disable_basic_irqs: u32,
};

routing_lock: TicketLock = TicketLock.init("irq routing", true),
routing: [max_irq_id]IrqRouting = undefined,
registers: *volatile Registers,
core_sources: [4]*volatile u32,

fn routeAddFromId(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();
    self.routing[id] = IrqRouting.mk(id);
}

pub fn init(allocator: Allocator, register_base: u64) !*Self {
    var self: *Self = try allocator.create(Self);

    self.registers = @ptrFromInt(register_base);

    for (0..max_irq_id) |id| {
        self.routing[id] = IrqRouting.from(@truncate(id));
    }

    for (0..3) |core| {
        self.core_sources[core] = @ptrFromInt(0x4000_0060 + (4 * core));
    }

    return self;
}

pub fn connect(self: *Self, id: IrqId, handler: *IrqHandler, private: *anyopaque) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    self.routing[id].handler = handler;
    self.routing[id].private = private;
}

pub fn disconnect(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    self.routing[id].handler = null;
}

pub fn enable(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    const basic = self.routing[id].enable_mask_basic;
    const extended = self.routing[id].enable_mask_extended;

    if (basic != 0) {
        self.registers.enable_basic_irqs = basic;
    }

    if (extended & 0xffff_ffff != 0) {
        self.registers.enable_irqs_1 = @as(u32, @truncate(extended)) & 0xffff_ffff;
    }

    if ((extended >> 32) & 0xffff_ffff != 0) {
        self.registers.enable_irqs_2 = @as(u32, @truncate(extended >> 32));
    }
}

pub fn disable(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    const basic = self.routing[id].enable_mask_basic;
    const extended = self.routing[id].enable_mask_extended;

    if (basic != 0) {
        self.registers.disable_basic_irqs = basic;
    }

    if (extended & 0xffff_ffff != 0) {
        self.registers.disable_irqs_1 = @as(u32, @truncate(extended & 0xffff_ffff));
    }

    if ((extended >> 32) & 0xffff_ffff != 0) {
        self.registers.disable_irqs_2 = @as(u32, @truncate(extended >> 32));
    }
}

// ----------------------------------------------------------------------
// Specific to interrupt routing on BCM2835 - 2837
// ----------------------------------------------------------------------

fn invokeHandler(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    const route = self.routing[id];
    self.routing_lock.release();

    route.invoke(self, id);
}

pub fn irqHandle(self: *Self, context: *const ExceptionContext) void {
    _ = context;

    var core_interrupts = self.core_sources[0].*;

    var basic_interrupts = self.registers.irq_pending[0];
    var pending_1_received: bool = false;
    var pending_2_received: bool = false;

    const cntvirq_interrupt: u32 = 0x08;
    if ((core_interrupts & cntvirq_interrupt) != 0) {
        self.invokeHandler(Irq.ARM_TIMER);
    }

    while (basic_interrupts != 0) {
        const next_bit_set: u5 = @truncate(@ctz(basic_interrupts));

        switch (next_bit_set) {
            0 => {
                // ARM CPU timer
                self.invokeHandler(Irq.ARM_TIMER);
            },
            8 => {
                // handle all pending_1 later
                pending_1_received = true;
            },
            9 => {
                // handle all pending_2 later
                pending_2_received = true;
            },
            11 => {
                // Basic IRQ bit 11 -> GPU IRQ 9 -> USB_HCI
                self.invokeHandler(Irq.USB_HCI);
            },
            19 => {
                // Basic IRQ bit 19 -> GPU IRQ 57 -> UART
                self.invokeHandler(Irq.UART);
            },
            else => {
                // do nothing
            },
        }

        basic_interrupts &= ~(@as(u32, 1) << next_bit_set);
    }

    // Handle the pending 1 interupts, but mask off ones which we
    // already would have handled.
    if (pending_1_received) {
        var pending_1 = self.registers.irq_pending[1];
        while (pending_1 != 0) {
            const next_bit_set: u6 = @ctz(pending_1);
            const irq_id = @as(IrqId, next_bit_set + 32);
            switch (irq_id) {
                Irq.TIMER_0,
                Irq.TIMER_1,
                Irq.TIMER_2,
                Irq.TIMER_3,
                => {
                    self.invokeHandler(irq_id);
                },
                Irq.GPU_7,
                Irq.USB_HCI,
                Irq.GPU_10,
                Irq.GPU_18,
                Irq.GPU_19,
                => {
                    // already handled, these were presented on the basic register
                },
                else => {},
            }
            pending_1 &= ~(@as(u32, 1) << @truncate(next_bit_set));
        }
    }

    if (pending_2_received) {
        var pending_2 = self.registers.irq_pending[2];
        while (pending_2 != 0) {
            const next_bit_set: u6 = @ctz(pending_2);
            const irq_id = @as(IrqId, next_bit_set + @as(IrqId, 64));
            switch (irq_id) {
                Irq.GPIO_0,
                Irq.GPIO_1,
                Irq.GPIO_2,
                Irq.GPIO_3,
                => {
                    self.invokeHandler(irq_id);
                },
                Irq.I2C,
                Irq.SPI,
                Irq.PCM,
                Irq.GPU_56,
                Irq.UART,
                Irq.GPU_62,
                => {
                    // already handled, these were presented on the basic register
                },
                else => {},
            }
            pending_2 &= ~(@as(u32, 1) << @truncate(next_bit_set));
        }
    }
}
