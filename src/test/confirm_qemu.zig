/// Run tests on the target architecture using Qemu
///
/// On success, this causes Qemu to exit with exit code 0.
/// Any other exit code indicates failure.

// expected_output
// end_expected_output

const helpers = @import("helpers.zig");

pub fn testBody() void {
    helpers.exit(0);
}
