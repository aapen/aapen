const root = @import("root");

const helpers = @import("helpers.zig");
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const stack = @import("../forty/stack.zig");
const Stack = stack.Stack;

pub fn testBody() !void {
    try basicStackOperation();
}

fn basicStackOperation() !void {
    const allocator = root.os.heap.page_allocator;

    const DStack = Stack(i32);
    var dstack = DStack.init(&allocator);
    defer dstack.deinit();

    const RStack = Stack(u16);
    var rstack = RStack.init(&allocator);
    defer rstack.deinit();

    for (0..7) |i| {
        try dstack.push(@as(i32, @intCast(i)) * 10);
        try rstack.push(@as(u16, @intCast(i)));
    }

    expectEqual(@as(usize, 7), dstack.depth());
    expectEqual(@as(usize, 7), rstack.depth());

    while (!dstack.isEmpty()) {
        _ = try dstack.pop();
    }

    expectEqual(@as(usize, 0), dstack.depth());

    while (!rstack.isEmpty()) {
        _ = try rstack.pop();
    }

    expectEqual(@as(usize, 0), rstack.depth());
}
