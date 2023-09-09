const bsp = @import("../bsp.zig");
const InterruptController = bsp.common.InterruptController;
const IrqId = bsp.common.IrqId;
const IrqHandlerFn = bsp.common.IrqHandlerFn;

const exceptions = @import("../architecture.zig").cpu.exceptions;
const ExceptionContext = exceptions.ExceptionContext;

// ----------------------------------------------------------------------
// Interrupt controller
// ----------------------------------------------------------------------

fn nullHandler(_: IrqId, _: ?*anyopaque) void {}

const HandlerThunk = struct {
    handler: IrqHandlerFn,
    context: ?*anyopaque,
};

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

    handlers: [96]HandlerThunk = undefined,
    registers: *volatile Registers = undefined,

    pub fn init(self: *LocalInterruptController, interrupt_controller_base: u64) void {
        self.registers = @ptrFromInt(interrupt_controller_base);

        for (0..3) |cell| {
            for (0..32) |bit| {
                self.disconnect(IrqId{ @truncate(cell), @truncate(bit) });
            }
        }
    }

    pub fn controller(self: *LocalInterruptController) bsp.common.InterruptController {
        return bsp.common.InterruptController.init(self, connect, disconnect, enable, disable);
    }

    pub fn connect(self: *LocalInterruptController, id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void {
        const idx: usize = @as(usize, id[0]) * 32 + id[1];
        self.handlers[idx].handler = handler;
        self.handlers[idx].context = context;
    }

    pub fn enable(self: *LocalInterruptController, id: IrqId) void {
        const bit: u32 = @as(u32, 1) << id[1];
        switch (id[0]) {
            0 => self.registers.enable_basic_irqs = bit,
            1 => self.registers.enable_irqs_1 = bit,
            2 => self.registers.enable_irqs_2 = bit,
            else => {},
        }
    }

    pub fn disable(self: *LocalInterruptController, id: IrqId) void {
        const mask: u32 = @as(u32, 1) << id[1];
        switch (id[0]) {
            0 => self.registers.disable_basic_irqs = mask,
            1 => self.registers.disable_irqs_1 = mask,
            2 => self.registers.disable_irqs_2 = mask,
            else => {},
        }
    }

    pub fn disconnect(self: *LocalInterruptController, id: IrqId) void {
        const idx: usize = @as(usize, id[0]) * 32 + id[1];
        self.handlers[idx].handler = nullHandler;
        self.handlers[idx].context = null;
    }

    inline fn handle(self: *LocalInterruptController, id: IrqId) void {
        const idx: usize = @as(usize, id[0]) * 32 + id[1];
        const thunk = self.handlers[idx];
        thunk.handler(id, thunk.context);
    }

    inline fn basicIrqHandleIfRaised(self: *LocalInterruptController, pending: u32, comptime bit: u5, comptime irq_id: IrqId) void {
        const check: u32 = (1 << bit);
        if ((pending & check) != 0) {
            self.handle(irq_id);
        }
    }

    pub fn irqHandle(self: *LocalInterruptController, _: *const ExceptionContext) void {
        const basic_interrupts = self.registers.irq_pending[0];
        const pending_1_received = (basic_interrupts & @as(u32, (1 << 8))) != 0;
        const pending_2_received = (basic_interrupts & @as(u32, (1 << 9))) != 0;

        // process basic interrupts before anything else
        self.basicIrqHandleIfRaised(basic_interrupts, 0, IrqId{ 0, 0 });
        self.basicIrqHandleIfRaised(basic_interrupts, 1, IrqId{ 0, 1 });
        self.basicIrqHandleIfRaised(basic_interrupts, 2, IrqId{ 0, 2 });
        self.basicIrqHandleIfRaised(basic_interrupts, 3, IrqId{ 0, 3 });
        self.basicIrqHandleIfRaised(basic_interrupts, 4, IrqId{ 0, 4 });
        self.basicIrqHandleIfRaised(basic_interrupts, 5, IrqId{ 0, 5 });
        self.basicIrqHandleIfRaised(basic_interrupts, 6, IrqId{ 0, 6 });
        self.basicIrqHandleIfRaised(basic_interrupts, 7, IrqId{ 0, 7 });

        // These are presented on the basic IRQ register but actually come
        // from GPU IRQs.
        //
        // I know there's no rhyme nor reason to this mapping. It's just
        // how the damn thing is wired.
        self.basicIrqHandleIfRaised(basic_interrupts, 10, IrqId{ 1, 7 });
        self.basicIrqHandleIfRaised(basic_interrupts, 11, IrqId{ 1, 9 });
        self.basicIrqHandleIfRaised(basic_interrupts, 12, IrqId{ 1, 10 });
        self.basicIrqHandleIfRaised(basic_interrupts, 13, IrqId{ 1, 18 });
        self.basicIrqHandleIfRaised(basic_interrupts, 14, IrqId{ 1, 19 });
        self.basicIrqHandleIfRaised(basic_interrupts, 15, IrqId{ 2, 21 });
        self.basicIrqHandleIfRaised(basic_interrupts, 16, IrqId{ 2, 22 });
        self.basicIrqHandleIfRaised(basic_interrupts, 17, IrqId{ 2, 23 });
        self.basicIrqHandleIfRaised(basic_interrupts, 18, IrqId{ 2, 24 });
        self.basicIrqHandleIfRaised(basic_interrupts, 19, IrqId{ 2, 25 });
        self.basicIrqHandleIfRaised(basic_interrupts, 20, IrqId{ 2, 30 });

        // Handle the pending 1 interupts, but mask off ones which we
        // already would have handled.
        if (pending_1_received) {
            const mask_basics: u32 = ~@as(u32, ((1 << 7) | (1 << 9) | (1 << 10) | (1 << 18) | (1 << 19)));
            var pending_1 = self.registers.irq_pending[1] & mask_basics;

            for (0..32) |b| {
                if (0 != (pending_1 & 0x1)) {
                    self.handle(IrqId{ 1, @as(u5, @truncate(b)) });
                }
                pending_1 >>= 1;
            }
        }

        if (pending_2_received) {
            const mask_basics: u32 = ~@as(u32, ((1 << 21) | (1 << 22) | (1 << 23) | (1 << 24) | (1 << 25) | (1 << 30)));
            var pending_2 = self.registers.irq_pending[2] & mask_basics;

            for (0..32) |b| {
                if (0 != (pending_2 & 0x1)) {
                    self.handle(IrqId{ 2, @as(u5, @truncate(b)) });
                }
                pending_2 >>= 1;
            }
        }
    }
};
