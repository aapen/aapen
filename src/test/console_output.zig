const helpers = @import("helpers.zig");

// expected_output
// Hello, world!
// end_expected_output

const serial = @import("../serial.zig");

pub fn testBody() void {
    serial.writer.print("Hello, world!", .{}) catch {};

    helpers.exit(0);
}
