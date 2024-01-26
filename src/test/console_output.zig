// expected_output
// Hello, world!
// Hello from printf!
// end_expected_output

const root = @import("root");
const serial = @import("../serial.zig");

pub fn testBody() !void {
    serial.writer.print("Hello, world!\n", .{}) catch {};
    _ = root.printf("Hello from %s!\n", "printf");
}
