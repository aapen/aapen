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

pub const IrqId = struct { u2, u5 };
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
                @call(.always_inline, ptr_info.Pointer.child.connect, .{ self, id, handler, context });
            }

            fn disconnect(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.always_inline, ptr_info.Pointer.child.disconnect, .{ self, id });
            }

            fn enable(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.always_inline, ptr_info.Pointer.child.enable, .{ self, id });
            }

            fn disable(ptr: *anyopaque, id: IrqId) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.always_inline, ptr_info.Pointer.child.disable, .{ self, id });
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
    ) Clock {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn ticks(ptr: *anyopaque) u64 {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.ticks, .{self});
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
    ) Timer {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn schedule(ptr: *anyopaque, delta: u32, callback: TimerCallbackFn, context: ?*anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.always_inline, ptr_info.Pointer.child.schedule, .{ self, delta, callback, context });
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
    ) Serial {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn getc(ptr: *anyopaque) u8 {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.getc, .{self});
            }

            fn putc(ptr: *anyopaque, ch: u8) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.putc, .{ self, ch });
            }

            fn puts(ptr: *anyopaque, buf: []const u8) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.puts, .{ self, buf });
            }

            fn hasc(ptr: *anyopaque) bool {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.hasc, .{self});
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

// ----------------------------------------------------------------------
// Generic Video Controller
// ----------------------------------------------------------------------
pub const VideoController = struct {
    ptr: *anyopaque,
    allocFrameBufferFn: *const fn (ptr: *anyopaque, fb: *FrameBuffer, xres: u32, yres: u32, depth: u32, palette: []const u32) void,

    pub fn init(
        pointer: anytype,
    ) VideoController {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn allocFrameBuffer(ptr: *anyopaque, fb: *FrameBuffer, xres: u32, yres: u32, depth: u32, palette: []const u32) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.allocFrameBuffer, .{
                    self,
                    fb,
                    xres,
                    yres,
                    depth,
                    palette,
                });
            }
        };

        return .{
            .ptr = pointer,
            .allocFrameBufferFn = generic.allocFrameBuffer,
        };
    }

    pub fn allocFrameBuffer(video_controller: *VideoController, fb: *FrameBuffer, xres: u32, yres: u32, depth: u32, palette: []const u32) void {
        video_controller.allocFrameBufferFn(video_controller.ptr, fb, xres, yres, depth, palette);
    }
};

// ----------------------------------------------------------------------
// Generic Board Info
// ----------------------------------------------------------------------

pub const BoardInfo = struct {
    pub const Model = struct {
        name: []const u8 = undefined,
        version: ?u8 = null,
        processor: []const u8 = undefined,
        memory: ?u32 = null,
        pcb_revision: ?u32 = null,
    };

    pub const Device = struct {
        manufacturer: []const u8 = undefined,
        serial_number: ?u32 = null,
        mac_address: ?u32 = null,
    };

    pub const Memory = struct {
        regions: memory.Regions = undefined,
    };

    model: Model = Model{},
    device: Device = Device{},
    memory: Memory = Memory{},

    pub fn init(self: *BoardInfo, allocator: *Allocator) void {
        self.memory.regions = memory.Regions.init(allocator.*);
    }
};

pub const BoardInfoController = struct {
    ptr: *anyopaque,
    inspectFn: *const fn (ptr: *anyopaque, info: *BoardInfo) void,

    pub fn init(
        pointer: anytype,
    ) BoardInfoController {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn inspect(ptr: *anyopaque, info: *BoardInfo) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                return @call(.always_inline, ptr_info.Pointer.child.inspect, .{ self, info });
            }
        };

        return .{
            .ptr = pointer,
            .inspectFn = generic.inspect,
        };
    }

    pub fn inspect(controller: *BoardInfoController, info: *BoardInfo) void {
        controller.inspectFn(controller.ptr, info);
    }
};

// ------------------------------------------------------------------------------
// Generic DMA driver
// ------------------------------------------------------------------------------
pub const DMAController = struct {
    ptr: *anyopaque,
    initiateFn: *const fn (controller: *anyopaque, source: u64, destination: u64, len: usize, stride: usize) void,

    pub fn init(
        pointer: anytype,
    ) DMAController {
        const Ptr = @TypeOf(pointer);
        const ptr_info = @typeInfo(Ptr);

        assert(@typeInfo(Ptr) == .Pointer);
        assert(@typeInfo(Ptr).Pointer.size == .One);
        assert(@typeInfo(@typeInfo(Ptr).Pointer.child) == .Struct);

        const generic = struct {
            fn initiate(ptr: *anyopaque, source: u64, dest: u64, len: usize, stride: usize) void {
                const self: Ptr = @ptrCast(@alignCast(ptr));
                @call(.always_inline, ptr_info.Pointer.child.initiate, .{ self, source, dest, len, stride });
            }
        };

        return .{
            .ptr = pointer,
            .initiateFn = generic.initiate,
        };
    }

    pub fn initiate(controller: *DMAController, source: u64, dest: u64, len: usize, stride: usize) void {
        controller.initiateFn(controller.ptr, source, dest, len, stride);
    }
};
