const root = @import("root");
const printf = root.printf;

const helpers = @import("helpers.zig");

pub const atomic = @import("atomic.zig").testBody;
pub const bcd = @import("bcd.zig").testBody;
pub const confirm_qemu = @import("confirm_qemu.zig").testBody;
pub const console_output = @import("console_output.zig").testBody;
pub const event = @import("event.zig").testBody;
pub const root_hub = @import("root_hub.zig").testBody;
pub const stack = @import("stack.zig").testBody;
pub const string = @import("string.zig").testBody;
pub const synchronize = @import("synchronize.zig").testBody;
pub const transfer = @import("transfer.zig").testBody;
pub const transfer_factory = @import("transfer_factory.zig").testBody;

pub fn locateTest(comptime testname: []const u8) fn () void {
    const test_fn = @field(@This(), testname);
    const Runner = struct {
        pub fn execute() void {
            helpers.allocator = root.os.heap.page_allocator;
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