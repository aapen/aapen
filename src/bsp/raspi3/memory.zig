pub const heap_start: *u64 = @extern(*u64, .{ .name = "__heap_start" });
pub const heap_end: *u64 = @extern(*u64, .{ .name = "__heap_end_exclusive" });

pub fn get_heap_bounds() struct { *u64, *u64 } {
    return .{ heap_start, heap_end };
}
