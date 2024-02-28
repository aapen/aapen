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
pub const max_irq_id = 64;

pub const IrqId = enum(u6) {
    TIMER_0 = 0,
    TIMER_1 = 1,
    TIMER_2 = 2,
    TIMER_3 = 3,
    USB_HCI = 9,
    GPIO_0 = 49,
    GPIO_1 = 50,
    GPIO_2 = 51,
    GPIO_3 = 52,
    UART = 57,
};

const IrqRouting = struct {
    enable_mask_basic: u32,
    enable_mask_extended: u64,
    handler: ?*IrqHandler,

    fn mk(en: u32, enx: u64) IrqRouting {
        return .{
            .enable_mask_basic = en,
            .enable_mask_extended = enx,
            .handler = null,
        };
    }
};

pub const IrqHandler = struct {
    callback: *const fn (*IrqHandler, *Self, IrqId) void,

    fn invoke(this: *IrqHandler, controller: *Self, id: IrqId) void {
        this.callback(this, controller, id);
    }
};

// ----------------------------------------------------------------------
// Interrupt controller
// ----------------------------------------------------------------------

const null_handler: IrqHandler = .{
    .callback = do_nothing,
};

fn do_nothing(_: *IrqHandler, _: *Self) void {}

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

routing_lock: TicketLock = TicketLock.initWithTargetLevel("irq routing", true, .FIQ),
routing: [max_irq_id]IrqRouting = undefined,
registers: *volatile Registers,

fn routeAddFromId(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    const index = @intFromEnum(id);
    const enable_extended = @as(u64, 1) << index;
    self.routing[index] = IrqRouting.mk(0, enable_extended);
}

pub fn init(allocator: Allocator, register_base: u64) !*Self {
    var self: *Self = try allocator.create(Self);

    self.registers = @ptrFromInt(register_base);

    for (0..max_irq_id) |id| {
        self.routing[id] = IrqRouting.mk(0, id);
    }

    self.routeAddFromId(.TIMER_0);
    self.routeAddFromId(.TIMER_1);
    self.routeAddFromId(.TIMER_2);
    self.routeAddFromId(.TIMER_3);
    self.routeAddFromId(.USB_HCI);
    self.routeAddFromId(.GPIO_0);
    self.routeAddFromId(.GPIO_1);
    self.routeAddFromId(.GPIO_2);
    self.routeAddFromId(.GPIO_3);
    self.routeAddFromId(.UART);

    return self;
}

pub fn connect(self: *Self, id: IrqId, handler: *IrqHandler) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    self.routing[@intFromEnum(id)].handler = handler;
}

pub fn disconnect(self: *Self, id: IrqId) void {
    self.routing_lock.acquire();
    defer self.routing_lock.release();

    self.routing[@intFromEnum(id)].handler = &null_handler;
}

pub fn enable(self: *Self, id: IrqId) void {
    const index = @intFromEnum(id);
    const basic = self.routing[index].enable_mask_basic;
    const extended = self.routing[index].enable_mask_extended;

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
    const index = @intFromEnum(id);
    const basic = self.routing[index].enable_mask_basic;
    const extended = self.routing[index].enable_mask_extended;

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
    const index = @intFromEnum(id);

    self.routing_lock.acquire();
    const route = &self.routing[index];
    self.routing_lock.release();

    if (route.handler) |h| {
        h.invoke(self, id);
    }
}

pub fn irqHandle(self: *Self, context: *const ExceptionContext) void {
    _ = context;

    var basic_interrupts = self.registers.irq_pending[0];
    var pending_1_received: bool = false;
    var pending_2_received: bool = false;

    while (basic_interrupts != 0) {
        const next: u5 = @truncate(@ctz(basic_interrupts));

        switch (next) {
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
                self.invokeHandler(.USB_HCI);
            },
            19 => {
                self.invokeHandler(.UART);
            },
            else => {
                // do nothing
            },
        }

        basic_interrupts &= ~(@as(u32, 1) << next);
    }

    // Handle the pending 1 interupts, but mask off ones which we
    // already would have handled.
    if (pending_1_received) {
        var pending_1 = self.registers.irq_pending[1];
        while (pending_1 != 0) {
            const next: u5 = @truncate(@ctz(pending_1));
            switch (next) {
                0, 1, 2, 3 => {
                    self.invokeHandler(@enumFromInt(next));
                },
                7, 9, 10, 18, 19 => {
                    // already handled, these were presented on the basic register
                },
                else => {},
            }
            pending_1 &= ~(@as(u32, 1) << next);
        }
    }

    if (pending_2_received) {
        var pending_2 = self.registers.irq_pending[2];
        while (pending_2 != 0) {
            const next: u5 = @truncate(@ctz(pending_2));
            switch (next) {
                17, 18, 19, 20 => {
                    self.invokeHandler(@enumFromInt(next + @as(u6, 32)));
                },
                21, 22, 23, 24, 25, 30 => {
                    // already handled, these were presented on the basic register
                },
                else => {},
            }
            pending_2 &= ~(@as(u32, 1) << next);
        }
    }
}
