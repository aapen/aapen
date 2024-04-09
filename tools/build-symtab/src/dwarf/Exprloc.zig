const std = @import("std");
const dwarf = std.dwarf;
const expressions = dwarf.expressions;
const ExpressionContext = expressions.ExpressionContext;

// This is specific to the target platform
const options = expressions.ExpressionOptions{
    .addr_size = @sizeOf(u64),
    .endian = std.builtin.Endian.Little,
    .call_frame_context = false,
};

const ExpressionMachine = expressions.StackMachine(options);

pub const Location = union(enum) {
    unknown: void,
    absolute: u64,
};

pub fn evaluate(exprloc: []const u8, allocator: std.mem.Allocator) Location {
    var evaluator: ExpressionMachine = .{};

    if (evaluator.run(exprloc, allocator, .{}, null)) |maybe_value| {
        defer evaluator.deinit(allocator);
        if (maybe_value) |val| {
            if (val.asIntegral()) |abs_val| {
                return Location{ .absolute = abs_val };
            } else |_| {}
        }
    } else |_| {}

    return Location{ .unknown = {} };
}
