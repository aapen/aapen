/// Stub for Zig's OS interface
///
/// This only has a small slice of what Zig expects from an actual OS
/// implementation. Just enough to get allocation working.


pub const system = struct {};
pub const heap = @import("heap.zig");
