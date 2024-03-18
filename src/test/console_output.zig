// expected_output
// Hello, world!
// Hello from printf!
// end_expected_output

const root = @import("root");
const printf = root.printf;

const serial = @import("../serial.zig");

pub fn testBody() !void {
    serial.writer.print("Hello, world!\n", .{}) catch {};
    _ = printf("Hello from %s!\n", "printf");
}
