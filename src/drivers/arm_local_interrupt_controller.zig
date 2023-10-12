const hal = @import("../hal.zig");

const exceptions = @import("../architecture.zig").cpu.exceptions;
const ExceptionContext = exceptions.ExceptionContext;

// ----------------------------------------------------------------------
// Interrupt controller
// ----------------------------------------------------------------------

fn nullHandler(_: hal.common.IrqId, _: ?*anyopaque) void {}

fn nullHandler2(_: *anyopaque, _: hal.interfaces.IrqId) void {}

const Handler = struct {
    handler: hal.common.IrqHandlerFn,
    context: ?*anyopaque,
};

inline fn bit(b: u5) u32 {
    return @as(u32, 1) << b;
}

fn handlerIndex(c0: u32, c1: u32) usize {
    return c0 * 32 + c1;
}

pub fn mkid(c0: u32, c1: u32) hal.common.IrqId {
    return .{ .index = handlerIndex(c0, c1) };
}

fn handlerRegister(id: hal.common.IrqId) u2 {
    return @intCast(id.index / 32);
}

fn handlerBitMask(id: hal.common.IrqId) u32 {
    return @as(u32, 1) << @as(u5, @intCast(id.index % 32));
}

fn handlerRegister2(id: hal.interfaces.IrqId) u2 {
    return @intCast(id.index / 32);
}

fn handlerBitMask2(id: hal.interfaces.IrqId) u32 {
    return @as(u32, 1) << @as(u5, @intCast(id.index % 32));
}

pub const LocalInterruptController = struct {
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

    const max_handlers = handlerIndex(2, 32);

    interface: hal.interfaces.InterruptController = undefined,
    handlers: [max_handlers]Handler = undefined,
    handlers2: [max_handlers]hal.interfaces.IrqHandlerFn = undefined,
    registers: *volatile Registers = undefined,

    pub fn init(self: *LocalInterruptController, interrupt_controller_base: u64) void {
        self.interface = .{
            .connect = connect2,
            .disconnect = disconnect2,
            .enable = enable2,
            .disable = disable2,
            .irqHandle = irqHandle2,
        };
        self.registers = @ptrFromInt(interrupt_controller_base);

        for (0..max_handlers) |i| {
            self.handlers[i].handler = nullHandler;
            self.handlers[i].context = null;
            self.handlers2[i] = nullHandler2;
        }
    }

    pub fn controller2(self: *LocalInterruptController) *hal.interfaces.InterruptController {
        return &self.interface;
    }

    fn connect2(intf: *hal.interfaces.InterruptController, id: hal.interfaces.IrqId, handler: hal.interfaces.IrqHandlerFn, context: *anyopaque) void {
        _ = context;
        const self = @fieldParentPtr(@This(), "interface", intf);

        self.handlers2[id.index] = handler;
        //        self.handlers2[id.index].context = context;
    }

    fn disconnect2(intf: *hal.interfaces.InterruptController, id: hal.interfaces.IrqId) void {
        const self = @fieldParentPtr(@This(), "interface", intf);

        self.handlers[id.index].handler = nullHandler;
        self.handlers[id.index].context = null;
    }

    fn enable2(intf: *hal.interfaces.InterruptController, id: hal.interfaces.IrqId) void {
        const self = @fieldParentPtr(@This(), "interface", intf);

        const mask = handlerBitMask2(id);
        switch (handlerRegister2(id)) {
            0 => self.registers.enable_basic_irqs = mask,
            1 => self.registers.enable_irqs_1 = mask,
            2 => self.registers.enable_irqs_2 = mask,
            else => {},
        }
    }

    fn disable2(intf: *hal.interfaces.InterruptController, id: hal.interfaces.IrqId) void {
        const self = @fieldParentPtr(@This(), "interface", intf);

        const mask = handlerBitMask2(id);
        switch (handlerRegister2(id)) {
            0 => self.registers.disable_basic_irqs = mask,
            1 => self.registers.disable_irqs_1 = mask,
            2 => self.registers.disable_irqs_2 = mask,
            else => {},
        }
    }

    fn irqHandle2(intf: *hal.interfaces.InterruptController, context: *const ExceptionContext) void {
        const self = @fieldParentPtr(@This(), "interface", intf);

        _ = context;

        const basic_interrupts = self.registers.irq_pending[0];
        const pending_1_received = (basic_interrupts & bit(8)) != 0;
        const pending_2_received = (basic_interrupts & bit(9)) != 0;

        // process basic interrupts before anything else
        self.basicIrqHandleIfRaised(basic_interrupts, bit(0), mkid(0, 0));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(1), mkid(0, 1));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(2), mkid(0, 2));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(3), mkid(0, 3));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(4), mkid(0, 4));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(5), mkid(0, 5));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(6), mkid(0, 6));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(7), mkid(0, 7));

        // These are presented on the basic IRQ register but actually come
        // from GPU IRQs.
        //
        // I know there's no rhyme nor reason to this mapping. It's just
        // how the damn thing is wired.
        self.basicIrqHandleIfRaised(basic_interrupts, bit(10), mkid(1, 7));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(11), mkid(1, 9));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(12), mkid(1, 10));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(13), mkid(1, 18));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(14), mkid(1, 19));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(15), mkid(2, 21));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(16), mkid(2, 22));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(17), mkid(2, 23));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(18), mkid(2, 24));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(19), mkid(2, 25));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(20), mkid(2, 30));

        // Handle the pending 1 interupts, but mask off ones which we
        // already would have handled.
        if (pending_1_received) {
            const mask_basics: u32 = ~@as(u32, (bit(7) | bit(9) | bit(10) | bit(18) | bit(19)));
            var pending_1 = self.registers.irq_pending[1] & mask_basics;

            for (0..32) |b| {
                if (0 != (pending_1 & 0x1)) {
                    self.handle(mkid(1, @as(u32, @truncate(b))));
                }
                pending_1 >>= 1;
            }
        }

        if (pending_2_received) {
            const mask_basics: u32 = ~@as(u32, (bit(21) | bit(22) | bit(23) | bit(24) | bit(25) | bit(30)));
            var pending_2 = self.registers.irq_pending[2] & mask_basics;

            for (0..32) |b| {
                if (0 != (pending_2 & 0x1)) {
                    self.handle(mkid(2, @as(u32, @truncate(b))));
                }
                pending_2 >>= 1;
            }
        }
    }

    pub fn controller(self: *LocalInterruptController) hal.common.InterruptController {
        return hal.common.InterruptController.init(self);
    }

    pub fn connect(self: *LocalInterruptController, id: hal.common.IrqId, handler: hal.common.IrqHandlerFn, context: *anyopaque) void {
        self.handlers[id.index].handler = handler;
        self.handlers[id.index].context = context;
    }

    pub fn enable(self: *LocalInterruptController, id: hal.common.IrqId) void {
        const mask = handlerBitMask(id);
        switch (handlerRegister(id)) {
            0 => self.registers.enable_basic_irqs = mask,
            1 => self.registers.enable_irqs_1 = mask,
            2 => self.registers.enable_irqs_2 = mask,
            else => {},
        }
    }

    pub fn disable(self: *LocalInterruptController, id: hal.common.IrqId) void {
        const mask = handlerBitMask(id);
        switch (handlerRegister(id)) {
            0 => self.registers.disable_basic_irqs = mask,
            1 => self.registers.disable_irqs_1 = mask,
            2 => self.registers.disable_irqs_2 = mask,
            else => {},
        }
    }

    pub fn disconnect(self: *LocalInterruptController, id: hal.common.IrqId) void {
        self.handlers[id.index].handler = nullHandler;
        self.handlers[id.index].context = null;
    }

    fn handle(self: *LocalInterruptController, id: hal.common.IrqId) void {
        const h = self.handlers[id.index];
        h.handler(id, h.context);
    }

    fn basicIrqHandleIfRaised(self: *LocalInterruptController, pending: u32, check: u32, irq_id: hal.common.IrqId) void {
        if ((pending & check) != 0) {
            self.handle(irq_id);
        }
    }

    pub fn irqHandle(self: *LocalInterruptController, context: *const ExceptionContext) void {
        _ = context;

        const basic_interrupts = self.registers.irq_pending[0];
        const pending_1_received = (basic_interrupts & bit(8)) != 0;
        const pending_2_received = (basic_interrupts & bit(9)) != 0;

        // process basic interrupts before anything else
        self.basicIrqHandleIfRaised(basic_interrupts, bit(0), mkid(0, 0));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(1), mkid(0, 1));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(2), mkid(0, 2));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(3), mkid(0, 3));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(4), mkid(0, 4));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(5), mkid(0, 5));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(6), mkid(0, 6));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(7), mkid(0, 7));

        // These are presented on the basic IRQ register but actually come
        // from GPU IRQs.
        //
        // I know there's no rhyme nor reason to this mapping. It's just
        // how the damn thing is wired.
        self.basicIrqHandleIfRaised(basic_interrupts, bit(10), mkid(1, 7));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(11), mkid(1, 9));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(12), mkid(1, 10));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(13), mkid(1, 18));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(14), mkid(1, 19));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(15), mkid(2, 21));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(16), mkid(2, 22));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(17), mkid(2, 23));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(18), mkid(2, 24));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(19), mkid(2, 25));
        self.basicIrqHandleIfRaised(basic_interrupts, bit(20), mkid(2, 30));

        // Handle the pending 1 interupts, but mask off ones which we
        // already would have handled.
        if (pending_1_received) {
            const mask_basics: u32 = ~@as(u32, (bit(7) | bit(9) | bit(10) | bit(18) | bit(19)));
            var pending_1 = self.registers.irq_pending[1] & mask_basics;

            for (0..32) |b| {
                if (0 != (pending_1 & 0x1)) {
                    self.handle(mkid(1, @as(u32, @truncate(b))));
                }
                pending_1 >>= 1;
            }
        }

        if (pending_2_received) {
            const mask_basics: u32 = ~@as(u32, (bit(21) | bit(22) | bit(23) | bit(24) | bit(25) | bit(30)));
            var pending_2 = self.registers.irq_pending[2] & mask_basics;

            for (0..32) |b| {
                if (0 != (pending_2 & 0x1)) {
                    self.handle(mkid(2, @as(u32, @truncate(b))));
                }
                pending_2 >>= 1;
            }
        }
    }
};
