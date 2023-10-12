const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const arch = @import("../architecture.zig");

const frame_buffer = @import("../frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const memory = @import("../memory.zig");
const Regions = memory.Regions;
const Region = memory.Region;

// ----------------------------------------------------------------------
// Generic Interrupt Controller
// ----------------------------------------------------------------------

pub const IrqId = struct {
    index: usize = undefined,
};

pub const IrqHandlerFn = *const fn (irq_id: IrqId, context: ?*anyopaque) void;
pub const IrqThunk = *const fn (context: *const arch.cpu.exceptions.ExceptionContext) void;

pub const InterruptController = struct {
    ptr: *anyopaque,
    connectFn: *const fn (controller: *anyopaque, id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void,
    disconnectFn: *const fn (controller: *anyopaque, id: IrqId) void,
    enableFn: *const fn (controller: *anyopaque, id: IrqId) void,
    disableFn: *const fn (controller: *anyopaque, id: IrqId) void,

    pub fn init(
        pointer: anytype,
    ) InterruptController {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn connect(ptr: *anyopaque, id: IrqId, handler: IrqHandlerFn, context: *anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.auto, ptr_info.Pointer.child.connect, .{ self, id, handler, context });
            }

            fn disconnect(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.auto, ptr_info.Pointer.child.disconnect, .{ self, id });
            }

            fn enable(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.auto, ptr_info.Pointer.child.enable, .{ self, id });
            }

            fn disable(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.auto, ptr_info.Pointer.child.disable, .{ self, id });
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
// Generic USB Controller
// ----------------------------------------------------------------------

pub const USB = struct {
    ptr: *anyopaque,
    powerFn: *const fn (ptr: *anyopaque, on_off: bool) void,

    pub fn init(
        pointer: anytype,
    ) USB {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn power(ptr: *anyopaque, on_off: bool) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.power, .{ self, on_off });
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
