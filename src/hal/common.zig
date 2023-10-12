const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const arch = @import("../architecture.zig");

const frame_buffer = @import("../frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

const memory = @import("../memory.zig");
const Regions = memory.Regions;
const Region = memory.Region;
