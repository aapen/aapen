// expected_output
// Hello, world!
// Hello from printf!
// end_expected_output

const root = @import("root");
const printf = root.printf;

const term = @import("../term.zig");

pub fn testBody() !void {
    term.writer.print("Hello, world!\n", .{}) catch {};
    _ = printf("Hello from %s!\n", "printf");
}
