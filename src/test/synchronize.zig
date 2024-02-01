const helpers = @import("helpers.zig");
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const synchronize = @import("../synchronize.zig");
const TicketLock = synchronize.TicketLock;

pub fn testBody() !void {
    try ticketLock();
}

fn ticketLock() !void {
    var lock: TicketLock = TicketLock.init("test ticket", true);

    lock.acquire();
    defer lock.release();
}
