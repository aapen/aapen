const exceptions = @import("../../architecture.zig").cpu.exceptions;
const ExceptionContext = exceptions.ExceptionContext;

pub const IrqId = struct {
    index: usize = undefined,
};

pub const IrqHandlerFn = *const fn (interrupt_controller: *anyopaque, irq_id: IrqId) void;

pub const InterruptController = struct {
    connect: *const fn (interrupt_controller: *InterruptController, id: IrqId, handler: IrqHandlerFn) void,
    disconnect: *const fn (interrupt_controller: *InterruptController, id: IrqId) void,
    enable: *const fn (interrupt_controller: *InterruptController, id: IrqId) void,
    disable: *const fn (interrupt_controller: *InterruptController, id: IrqId) void,

    irqHandle: *const fn (interrupt_controller: *InterruptController, context: *const ExceptionContext) void,
};
