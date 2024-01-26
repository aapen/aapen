const root = @import("root");
const printf = root.printf;

const helpers = @import("helpers.zig");

pub const confirm_qemu = @import("confirm_qemu.zig").testBody;
pub const console_output = @import("console_output.zig").testBody;
pub const bcd = @import("bcd.zig").testBody;

pub const TestFn = fn () void;

pub fn locateTest(comptime testname: []const u8) TestFn {
    const test_fn = @field(@This(), testname);
    const Runner = struct {
        pub fn execute() void {
            _ = printf("=== %s\n", testname.ptr);
            if (test_fn()) {
                helpers.exitWithTestResult();
            } else |err| {
                _ = printf("%s\n", @errorName(err).ptr);
                helpers.exit(254);
            }
        }
    };
    return Runner.execute;
}
