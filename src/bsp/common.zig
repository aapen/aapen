const std = @import("std");
const assert = std.debug.assert;

// ----------------------------------------------------------------------
// Generic Interrupt Controller
// ----------------------------------------------------------------------

pub const IrqId = struct { u2, u5 };
pub const IrqHandlerFn = *const fn (irq_id: IrqId, context: ?*anyopaque) void;

pub const InterruptController = struct {
    ptr: *anyopaque,
    connectFn: *const fn (controller: *anyopaque, id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void,
    disconnectFn: *const fn (controller: *anyopaque, id: IrqId) void,
    enableFn: *const fn (controller: *anyopaque, id: IrqId) void,
    disableFn: *const fn (controller: *anyopaque, id: IrqId) void,

    pub fn init(
        pointer: anytype,
        comptime connectFn: fn (ptr: @TypeOf(pointer), id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void,
        comptime disconnectFn: *const fn (ptr: @TypeOf(pointer), id: IrqId) void,
        comptime enableFn: *const fn (ptr: @TypeOf(pointer), id: IrqId) void,
        comptime disableFn: *const fn (ptr: @TypeOf(pointer), id: IrqId) void,
    ) InterruptController {
        const Ptr = @TypeOf(pointer);
        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn connect(ptr: *anyopaque, id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                connectFn(self, id, handler, context);
            }

            fn disconnect(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                disconnectFn(self, id);
            }

            fn enable(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                enableFn(self, id);
            }

            fn disable(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                disableFn(self, id);
            }
        };

        return .{
            .ptr = pointer,
            .connectFn = generic.connect,
            .disconnectFn = generic.disconnect,
            .enableFn = generic.enable,
            .disableFn = generic.disable,
        };
    }

    pub fn connect(controller: *InterruptController, id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void {
        return controller.connectFn(controller.ptr, id, handler, context);
    }

    pub fn disconnect(controller: *InterruptController, id: IrqId) void {
        return controller.disconnectFn(controller.ptr, id);
    }

    pub fn enable(controller: *InterruptController, id: IrqId) void {
        return controller.enableFn(controller.ptr, id);
    }

    pub fn disable(controller: *InterruptController, id: IrqId) void {
        return controller.disableFn(controller.ptr, id);
    }
};

// ----------------------------------------------------------------------
// Generic Clock
// ----------------------------------------------------------------------

pub const Clock = struct {
    ptr: *anyopaque,
    ticksFn: *const fn (ptr: *anyopaque) u64,

    pub fn init(
        pointer: anytype,
        comptime ticksFn: fn (ptr: @TypeOf(pointer)) u64,
    ) Clock {
        const Ptr = @TypeOf(pointer);
        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn ticks(ptr: *anyopaque) u64 {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return ticksFn(self);
            }
        };

        return .{
            .ptr = pointer,
            .ticksFn = generic.ticks,
        };
    }

    pub fn ticks(clock: *Clock) u64 {
        return clock.ticksFn(clock.ptr);
    }
};

// ----------------------------------------------------------------------
// Generic Timer
// ----------------------------------------------------------------------

pub const TimerCallbackFn = *const fn (context: ?*anyopaque) u32;

pub const Timer = struct {
    ptr: *anyopaque,
    scheduleFn: *const fn (ptr: *anyopaque, delta: u32, callback: TimerCallbackFn, context: ?*anyopaque) void,

    pub fn init(
        pointer: anytype,
        comptime scheduleFn: fn (ptr: @TypeOf(pointer), delta: u32, callback: TimerCallbackFn, context: ?*anyopaque) void,
    ) Timer {
        const Ptr = @TypeOf(pointer);
        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn schedule(ptr: *anyopaque, delta: u32, callback: TimerCallbackFn, context: ?*anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                scheduleFn(self, delta, callback, context);
            }
        };

        return .{
            .ptr = pointer,
            .scheduleFn = generic.schedule,
        };
    }

    pub fn schedule(timer: *Timer, delta: u32, callback: TimerCallbackFn, context: ?*anyopaque) void {
        return timer.scheduleFn(timer.ptr, delta, callback, context);
    }
};

// ----------------------------------------------------------------------
// Generic Serial
// ----------------------------------------------------------------------

pub const Serial = struct {
    ptr: *anyopaque,
    getcFn: *const fn (ptr: *anyopaque) u8,
    putcFn: *const fn (ptr: *anyopaque, ch: u8) void,
    putsFn: *const fn (ptr: *anyopaque, buf: []const u8) void,
    hascFn: *const fn (ptr: *anyopaque) bool,

    pub fn init(
        pointer: anytype,
        comptime getcFn: fn (ptr: @TypeOf(pointer)) u8,
        comptime putcFn: fn (ptr: @TypeOf(pointer), ch: u8) void,
        comptime putsFn: fn (ptr: @TypeOf(pointer), buf: []const u8) void,
        comptime hascFn: fn (ptr: @TypeOf(pointer)) bool,
    ) Serial {
        const Ptr = @TypeOf(pointer);
        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn getc(ptr: *anyopaque) u8 {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return getcFn(self);
            }

            fn putc(ptr: *anyopaque, ch: u8) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return putcFn(self, ch);
            }

            fn puts(ptr: *anyopaque, buf: []const u8) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return putsFn(self, buf);
            }

            fn hasc(ptr: *anyopaque) bool {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return hascFn(self);
            }
        };

        return .{
            .ptr = pointer,
            .getcFn = generic.getc,
            .putcFn = generic.putc,
            .putsFn = generic.puts,
            .hascFn = generic.hasc,
        };
    }

    pub fn getc(serial: *Serial) u8 {
        return serial.getcFn(serial.ptr);
    }

    pub fn putc(serial: *Serial, ch: u8) void {
        serial.putcFn(serial.ptr, ch);
    }

    pub fn puts(serial: *Serial, buffer: []const u8) void {
        serial.putsFn(serial.ptr, buffer);
    }

    pub fn hasc(serial: *Serial) bool {
        return serial.hascFn(serial.ptr);
    }
};

// ----------------------------------------------------------------------
// Generic USB Controller
// ----------------------------------------------------------------------

pub const USB = struct {
    ptr: *anyopaque,
    powerFn: *const fn (ptr: *anyopaque, on_off: bool) void,

    pub fn init(
        pointer: anytype,
        comptime powerFn: fn (ptr: @TypeOf(pointer), on_off: bool) void,
    ) USB {
        const Ptr = @TypeOf(pointer);
        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn power(ptr: *anyopaque, on_off: bool) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return powerFn(self, on_off);
            }
        };

        return .{
            .ptr = pointer,
            .powerFn = generic.power,
        };
    }

    pub fn powerOn(usb: *USB) void {
        usb.powerFn(usb.ptr, true);
    }

    pub fn powerOff(usb: *USB) void {
        usb.powerFn(usb.ptr, false);
    }
};
